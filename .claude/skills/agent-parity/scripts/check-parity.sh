#!/usr/bin/env bash
# check-parity.sh — runtime parity diff across detected agents.
# Compares each installed agent against claude (reference) — no manifest needed.
# Reports: GAP (one side has it, other doesn't), DRIFTED (both have it, content differs).
# Usage: check-parity.sh [--format prose|json] [--axis permissions|model|instructions|hooks|agent-definitions|all] [--agent opencode|codex|cursor]
set -euo pipefail

AXIS="all"
AGENT_FILTER=""
FORMAT="prose"

usage() {
  echo "Usage: check-parity.sh [--format prose|json] [--axis permissions|model|instructions|hooks|agent-definitions|all] [--agent opencode|codex|cursor]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --axis) [ $# -ge 2 ] || { usage; exit 2; }; AXIS="$2"; shift 2 ;;
    --axis=*) AXIS="${1#--axis=}"; shift ;;
    --agent) [ $# -ge 2 ] || { usage; exit 2; }; AGENT_FILTER="$2"; shift 2 ;;
    --agent=*) AGENT_FILTER="${1#--agent=}"; shift ;;
    --format) [ $# -ge 2 ] || { usage; exit 2; }; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#--format=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$FORMAT" in
  prose|json) ;;
  *) echo "Unknown format: $FORMAT (valid: prose, json)" >&2; exit 2 ;;
esac

case "$AXIS" in
  all|permissions|model|instructions|hooks|agent-definitions) ;;
  *) echo "Unknown axis: $AXIS (valid: permissions, model, instructions, hooks, agent-definitions, all)" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRACTORS_DIR="$SCRIPT_DIR/extractors"
DESCRIPTORS="${AGENT_PARITY_DESCRIPTORS:-$SCRIPT_DIR/../descriptors/agents.json}"
GAPS=0
WARNINGS=0
ACCEPTED=0
TMP_DIR="$(mktemp -d)"
GAPS_FILE="$TMP_DIR/gaps.jsonl"
WARNINGS_FILE="$TMP_DIR/warnings.jsonl"
ACCEPTED_FILE="$TMP_DIR/accepted.jsonl"
touch "$GAPS_FILE" "$WARNINGS_FILE" "$ACCEPTED_FILE"
trap 'rm -rf "$TMP_DIR"' EXIT

record_event() {
  local file="$1" kind="$2" label="$3" item="$4" agent="$5" side="${6:-}" reason="${7:-}" detail="${8:-}"
  jq -nc \
    --arg kind "$kind" \
    --arg label "$label" \
    --arg item "$item" \
    --arg agent "$agent" \
    --arg side "$side" \
    --arg reason "$reason" \
    --arg detail "$detail" \
    '{kind: $kind, label: $label, item: $item, agent: $agent, side: $side, reason: $reason, detail: $detail}
     | with_entries(select(.value != ""))' >> "$file"
}

count_file() {
  [ -s "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0
}

emit_json_report() {
  local gaps warnings accepted
  gaps="$(count_file "$GAPS_FILE")"
  warnings="$(count_file "$WARNINGS_FILE")"
  accepted="$(count_file "$ACCEPTED_FILE")"
  jq -n \
    --slurpfile gaps "$GAPS_FILE" \
    --slurpfile warnings "$WARNINGS_FILE" \
    --slurpfile accepted "$ACCEPTED_FILE" \
    --argjson gap_count "$gaps" \
    --argjson warning_count "$warnings" \
    --argjson accepted_count "$accepted" \
    '{gaps: $gaps, warnings: $warnings, accepted: $accepted, counts: {gaps: $gap_count, warnings: $warning_count, accepted: $accepted_count}}'
}

# --- Adapter loading ---
# Source the extractor for a given agent name. Sets EXTRACTOR_* env vars
# for adapter-specific paths before sourcing.
load_extractor() {
  local agent="$1"
  local adapter="$EXTRACTORS_DIR/${agent}.sh"
  if [ ! -f "$adapter" ]; then
    echo "ERROR: no extractor adapter for agent '$agent' at $adapter" >&2
    return 1
  fi

  # Set adapter env vars from detect-agents output
  export EXTRACTOR_HOOKS_DIR="$(get_agent_hooks "$agent")"
  export EXTRACTOR_HOOKS_FILE="$(get_agent_hooks "$agent")"
  export EXTRACTOR_PERMISSIONS_FILE="$(get_agent_permissions "$agent")"
  export EXTRACTOR_AGENT_DEFS_DIR="$(get_agent_defs_dir "$agent")"

  # shellcheck source=/dev/null
  source "$adapter"
}

# Get settings/instructions paths for an agent from detect-agents output
get_agent_settings() {
  echo "$AGENTS_JSON" | jq -r --arg a "$1" '.agents[] | select(.name==$a) | .settings // ""'
}

get_agent_instructions() {
  echo "$AGENTS_JSON" | jq -r --arg a "$1" '.agents[] | select(.name==$a) | .instructions // ""'
}

get_agent_hooks() {
  echo "$AGENTS_JSON" | jq -r --arg a "$1" '.agents[] | select(.name==$a) | .hooks // ""'
}

get_agent_permissions() {
  echo "$AGENTS_JSON" | jq -r --arg a "$1" '.agents[] | select(.name==$a) | .permissions // ""'
}

get_agent_defs_dir() {
  echo "$AGENTS_JSON" | jq -r --arg a "$1" '.agents[] | select(.name==$a) | .agent_definitions // ""'
}

# --- Agent detection ---
AGENTS_JSON="$(AGENT_PARITY_DESCRIPTORS="$DESCRIPTORS" "$SCRIPT_DIR/detect-agents.sh")"
INSTALLED=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.installed) | .name')
AGENT_COUNT=$(echo "$INSTALLED" | wc -w)

CLAUDE_INSTALLED=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="claude" and .installed) | .name')
OTHER_AGENTS=""

REFERENCE_AGENT="claude"
TODAY="$(date +%F)"

# Returns 0 with "past" on stdout if review_by is non-empty and before today.
is_past_review() {
  local review_by="$1"
  [ -n "$review_by" ] || return 1
  [ "$review_by" \< "$TODAY" ]
}

accepted_gap_reason() {
  local label="$1" other_name="$2" side="$3" item="$4" entry reason review_by

  entry=$(jq -c \
    --arg agent "$other_name" \
    --arg label "$label" \
    --arg side "$side" \
    --arg item "$item" \
    '.agents[]
     | select(.name == $agent)
     | .accepted_gaps[$label][$side][]?
     | select(.item == $item)' "$DESCRIPTORS")

  [ -n "$entry" ] || return 1
  reason=$(echo "$entry" | jq -r '.reason')
  review_by=$(echo "$entry" | jq -r '.review_by // empty')

  if is_past_review "$review_by"; then
    echo "PAST-REVIEW|$reason|$review_by"
    return 2
  fi
  echo "$reason"
}

accepted_model_reason() {
  local agent="$1" reason review_by

  reason=$(jq -r --arg agent "$agent" \
    '.agents[] | select(.name == $agent) | .accepted_model_reason // empty' \
    "$DESCRIPTORS")

  [ -n "$reason" ] || return 1
  review_by=$(jq -r --arg agent "$agent" \
    '.agents[] | select(.name == $agent) | .accepted_model_review_by // empty' \
    "$DESCRIPTORS")

  if is_past_review "$review_by"; then
    echo "PAST-REVIEW|$reason|$review_by"
    return 2
  fi
  echo "$reason"
}

# --- Diff helper: compare two sorted lists ---
diff_lists() {
  local label="$1"
  local ref_list="$2"
  local other_list="$3"
  local other_name="$4"
  local check_content="${5:-no}"

  local both only_ref only_other
  both=$(comm -12 <(echo "$ref_list") <(echo "$other_list") 2>/dev/null || true)
  only_ref=$(comm -23 <(echo "$ref_list") <(echo "$other_list") 2>/dev/null || true)
  only_other=$(comm -13 <(echo "$ref_list") <(echo "$other_list") 2>/dev/null || true)

  while IFS= read -r item; do
    [ -z "$item" ] && continue
    if [ "$check_content" = "yes" ]; then
      local c_path o_path
      load_extractor "$REFERENCE_AGENT" >/dev/null 2>&1
      c_path=$(extract_resolve_doc_path "$(get_agent_settings $REFERENCE_AGENT)" "$(get_agent_instructions $REFERENCE_AGENT)" "$item")
      load_extractor "$other_name" >/dev/null 2>&1
      o_path=$(extract_resolve_doc_path "$(get_agent_settings $other_name)" "$(get_agent_instructions $other_name)" "$item")
      if [ -n "$c_path" ] && [ -f "$c_path" ] && [ -n "$o_path" ] && [ -f "$o_path" ]; then
        if ! diff -q "$c_path" "$o_path" >/dev/null 2>&1; then
          printf "  DRIFTED: %-29s (content differs)\n" "$item"
          record_event "$WARNINGS_FILE" "DRIFTED" "$label" "$item" "$other_name" "" "" "content differs"
          WARNINGS=$((WARNINGS + 1))
          continue
        fi
      fi
    fi
    printf "  %-40s both\n" "$item"
  done <<< "$both"

  while IFS= read -r item; do
    [ -z "$item" ] && continue
    local reason status
    set +e
    reason=$(accepted_gap_reason "$label" "$other_name" "$REFERENCE_AGENT" "$item")
    status=$?
    set -e
    if [ "$status" -eq 2 ]; then
      local review_by base_reason
      base_reason="${reason#PAST-REVIEW|}"; base_reason="${base_reason%%|*}"
      review_by="${reason##*|}"
      printf "  PAST-REVIEW: %-25s (accepted exception past review date %s)\n" "$item" "$review_by"
      record_event "$WARNINGS_FILE" "PAST-REVIEW" "$label" "$item" "$other_name" "$REFERENCE_AGENT" "$base_reason" "review_by=$review_by"
      WARNINGS=$((WARNINGS + 1))
    elif [ "$status" -eq 0 ]; then
      printf "  ACCEPTED: %-29s %s only (%s)\n" "$item" "$REFERENCE_AGENT" "$reason"
      record_event "$ACCEPTED_FILE" "ACCEPTED" "$label" "$item" "$other_name" "$REFERENCE_AGENT" "$reason"
      ACCEPTED=$((ACCEPTED + 1))
    else
      printf "  GAP: %-34s %s only\n" "$item" "$REFERENCE_AGENT"
      record_event "$GAPS_FILE" "GAP" "$label" "$item" "$other_name" "$REFERENCE_AGENT"
      GAPS=$((GAPS + 1))
    fi
  done <<< "$only_ref"

  while IFS= read -r item; do
    [ -z "$item" ] && continue
    local reason status
    set +e
    reason=$(accepted_gap_reason "$label" "$other_name" "$other_name" "$item")
    status=$?
    set -e
    if [ "$status" -eq 2 ]; then
      local review_by base_reason
      base_reason="${reason#PAST-REVIEW|}"; base_reason="${base_reason%%|*}"
      review_by="${reason##*|}"
      printf "  PAST-REVIEW: %-25s (accepted exception past review date %s)\n" "$item" "$review_by"
      record_event "$WARNINGS_FILE" "PAST-REVIEW" "$label" "$item" "$other_name" "$other_name" "$base_reason" "review_by=$review_by"
      WARNINGS=$((WARNINGS + 1))
    elif [ "$status" -eq 0 ]; then
      printf "  ACCEPTED: %-29s %s only (%s)\n" "$item" "$other_name" "$reason"
      record_event "$ACCEPTED_FILE" "ACCEPTED" "$label" "$item" "$other_name" "$other_name" "$reason"
      ACCEPTED=$((ACCEPTED + 1))
    else
      printf "  GAP: %-34s %s only\n" "$item" "$other_name"
      record_event "$GAPS_FILE" "GAP" "$label" "$item" "$other_name" "$other_name"
      GAPS=$((GAPS + 1))
    fi
  done <<< "$only_other"
}

# --- Permissions axis ---
check_permissions() {
  echo "permissions:"
  load_extractor "$REFERENCE_AGENT"
  local ref_denies
  ref_denies=$(extract_denies "$(get_agent_settings $REFERENCE_AGENT)" | sort || true)
  for agent in $OTHER_AGENTS; do
    load_extractor "$agent"
    local other_denies
    other_denies=$(extract_denies "$(get_agent_settings $agent)" | sort || true)
    echo "  vs $agent:"
    diff_lists "deny" "$ref_denies" "$other_denies" "$agent"
  done
  echo ""
}

# --- Model axis ---
check_model() {
  echo "model:"
  load_extractor "$REFERENCE_AGENT"
  local ref_model
  ref_model=$(extract_model "$(get_agent_settings $REFERENCE_AGENT)")
  printf "  %s: %s\n" "$REFERENCE_AGENT" "${ref_model:-not set}"

  local ref_base
  ref_base=$(echo "$ref_model" | sed 's/\[.*\]//;s/^.*\///;s/\./-/g')

  for agent in $OTHER_AGENTS; do
    load_extractor "$agent"
    local a_model a_base
    a_model=$(extract_model "$(get_agent_settings $agent)")
    printf "  %s: %s\n" "$agent" "${a_model:-not set}"

    a_base=$(echo "$a_model" | sed 's/\[.*\]//;s/^.*\///;s/\./-/g')
    if [ "$ref_base" = "$a_base" ]; then
      echo "  MATCH (same base model)"
    else
      local reason status
      set +e
      reason=$(accepted_model_reason "$agent")
      status=$?
      set -e
      if [ "$status" -eq 2 ]; then
        local review_by base_reason
        base_reason="${reason#PAST-REVIEW|}"; base_reason="${base_reason%%|*}"
        review_by="${reason##*|}"
        echo "  PAST-REVIEW: model (accepted exception past review date $review_by)"
        record_event "$WARNINGS_FILE" "PAST-REVIEW" "model" "model" "$agent" "" "$base_reason" "review_by=$review_by; $REFERENCE_AGENT=${ref_model:-not set}, $agent=${a_model:-not set}"
        WARNINGS=$((WARNINGS + 1))
      elif [ "$status" -eq 0 ]; then
        echo "  ACCEPTED (different base model; $reason)"
        record_event "$ACCEPTED_FILE" "ACCEPTED" "model" "model" "$agent" "" "$reason" "$REFERENCE_AGENT=${ref_model:-not set}, $agent=${a_model:-not set}"
        ACCEPTED=$((ACCEPTED + 1))
      else
        echo "  DIVERGED (different base model)"
        record_event "$GAPS_FILE" "DIVERGED" "model" "model" "$agent" "" "" "$REFERENCE_AGENT=${ref_model:-not set}, $agent=${a_model:-not set}"
        GAPS=$((GAPS + 1))
      fi
    fi
  done
  echo ""
}

# --- Instructions axis ---
check_instructions() {
  echo "instructions:"
  load_extractor "$REFERENCE_AGENT"
  local ref_docs
  ref_docs=$(extract_docs "$(get_agent_settings $REFERENCE_AGENT)" "$(get_agent_instructions $REFERENCE_AGENT)" | sort || true)
  for agent in $OTHER_AGENTS; do
    load_extractor "$agent"
    local other_docs
    other_docs=$(extract_docs "$(get_agent_settings $agent)" "$(get_agent_instructions $agent)" | sort || true)
    if [ -z "$other_docs" ]; then
      echo "  vs $agent: (no file-based instruction surface)"
      continue
    fi
    echo "  vs $agent:"
    diff_lists "doc" "$ref_docs" "$other_docs" "$agent" "yes"
  done
  echo ""
}

# --- Hooks axis ---
check_hooks() {
  echo "hooks:"
  load_extractor "$REFERENCE_AGENT"
  local ref_hooks
  ref_hooks=$(extract_hooks "$(get_agent_settings $REFERENCE_AGENT)" | sort -u || true)
  for agent in $OTHER_AGENTS; do
    load_extractor "$agent"
    local other_hooks
    other_hooks=$(extract_hooks "$(get_agent_settings $agent)" | sort -u || true)
    echo "  vs $agent:"
    diff_lists "hook" "$ref_hooks" "$other_hooks" "$agent"
  done
  echo ""
}

# --- Agent definition axis ---
check_agent_definitions() {
  echo "agent-definitions:"
  load_extractor "$REFERENCE_AGENT"
  local ref_defs
  ref_defs=$(extract_agent_defs "$(get_agent_settings $REFERENCE_AGENT)" | sort || true)
  for agent in $OTHER_AGENTS; do
    load_extractor "$agent"
    local other_defs
    other_defs=$(extract_agent_defs "$(get_agent_settings $agent)" | sort || true)
    echo "  vs $agent:"
    diff_lists "agent-definition" "$ref_defs" "$other_defs" "$agent"
  done
  echo ""
}

run_report() {
  echo "agent-parity: $AGENT_COUNT agent(s) detected ($(echo $INSTALLED | tr '\n' ' ' | sed 's/ $//'))"
  echo ""

  if [ "$AGENT_COUNT" -lt 2 ]; then
    echo "Need at least 2 installed agents to compare."
    return 0
  fi

  if [ -z "$CLAUDE_INSTALLED" ]; then
    echo "Claude not installed; nothing to compare against."
    return 0
  fi

  OTHER_AGENTS=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.installed and .name!="claude") | .name')

  if [ -n "$AGENT_FILTER" ]; then
    if echo "$OTHER_AGENTS" | grep -qx "$AGENT_FILTER"; then
      OTHER_AGENTS="$AGENT_FILTER"
    else
      echo "Agent '$AGENT_FILTER' is not installed or is not comparable." >&2
      return 2
    fi
  fi

  case "$AXIS" in
    all)               check_permissions; check_model; check_instructions; check_hooks; check_agent_definitions ;;
    permissions)       check_permissions ;;
    model)             check_model ;;
    instructions)      check_instructions ;;
    hooks)             check_hooks ;;
    agent-definitions) check_agent_definitions ;;
  esac
}

set +e
PROSE_OUTPUT="$(run_report)"
RUN_STATUS=$?
set -e

GAPS="$(count_file "$GAPS_FILE")"
WARNINGS="$(count_file "$WARNINGS_FILE")"
ACCEPTED="$(count_file "$ACCEPTED_FILE")"

if [ "$FORMAT" = "json" ]; then
  emit_json_report
else
  [ -n "$PROSE_OUTPUT" ] && printf '%s\n' "$PROSE_OUTPUT"
  echo "summary: $GAPS gap(s), $WARNINGS warning(s), $ACCEPTED accepted exception(s)"
fi

[ "$RUN_STATUS" -eq 0 ] || exit "$RUN_STATUS"
[ $((GAPS + WARNINGS)) -eq 0 ] || exit 1
exit 0
