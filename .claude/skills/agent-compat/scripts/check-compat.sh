#!/usr/bin/env bash
# check-compat.sh — runtime compatibility diff across detected agents.
# Compares each installed agent against claude (reference) — no manifest needed.
# Reports: GAP (one side has it, other doesn't), DRIFTED (both have it, content differs).
# Usage: check-compat.sh [--format prose|json] [--axis permissions|model|instructions|hooks|agent-definitions|all] [--agent opencode|codex|cursor]
set -euo pipefail

AXIS="all"
AGENT_FILTER=""
FORMAT="prose"
SCOPE="global"

usage() {
  echo "Usage: check-compat.sh [--format prose|json] [--axis permissions|model|instructions|hooks|agent-definitions|skills|all] [--agent opencode|codex|cursor] [--scope global|project]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --axis) [ $# -ge 2 ] || { usage; exit 2; }; AXIS="$2"; shift 2 ;;
    --axis=*) AXIS="${1#--axis=}"; shift ;;
    --agent) [ $# -ge 2 ] || { usage; exit 2; }; AGENT_FILTER="$2"; shift 2 ;;
    --agent=*) AGENT_FILTER="${1#--agent=}"; shift ;;
    --format) [ $# -ge 2 ] || { usage; exit 2; }; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#--format=}"; shift ;;
    --scope) [ $# -ge 2 ] || { usage; exit 2; }; SCOPE="$2"; shift 2 ;;
    --scope=*) SCOPE="${1#--scope=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$FORMAT" in
  prose|json) ;;
  *) echo "Unknown format: $FORMAT (valid: prose, json)" >&2; exit 2 ;;
esac

case "$AXIS" in
  all|permissions|model|instructions|hooks|agent-definitions|skills) ;;
  *) echo "Unknown axis: $AXIS (valid: permissions, model, instructions, hooks, agent-definitions, skills, all)" >&2; exit 2 ;;
esac

case "$SCOPE" in
  global|project) ;;
  *) echo "Unknown scope: $SCOPE (valid: global, project)" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRACTORS_DIR="$SCRIPT_DIR/extractors"
DESCRIPTORS="${AGENT_COMPAT_DESCRIPTORS:-$SCRIPT_DIR/../descriptors/agents.json}"
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
  export EXTRACTOR_SKILLS_DIR="$(get_agent_skills_dir "$agent")"

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

get_agent_skills_dir() {
  echo "$AGENTS_JSON" | jq -r --arg a "$1" '.agents[] | select(.name==$a) | .skills // ""'
}

# --- Agent detection ---
AGENTS_JSON="$(AGENT_COMPAT_DESCRIPTORS="$DESCRIPTORS" "$SCRIPT_DIR/detect-agents.sh")"
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
     | select(.item == $item or .item == "*")' "$DESCRIPTORS" | head -1)

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

# --- Skills axis (global) ---
# extract_skills emits "name<TAB>resolved-real-path" per skill. The Claude-visible
# set is canonical: other agents must present the same names, each resolving to
# the same real path. GAP = name missing (fix printed as a ready-to-run ln -s);
# DRIFTED = broken symlink or resolved target differs.
check_skills() {
  echo "skills:"
  load_extractor "$REFERENCE_AGENT"
  local ref_skills
  ref_skills=$(extract_skills | sort || true)
  for agent in $OTHER_AGENTS; do
    load_extractor "$agent"
    local other_skills other_dir
    other_skills=$(extract_skills | sort || true)
    other_dir=$(get_agent_skills_dir "$agent")
    if [ -z "$other_skills" ]; then
      echo "  vs $agent: (no file-based skills surface)"
      continue
    fi
    echo "  vs $agent:"

    local ref_names other_names both only_ref only_other
    ref_names=$(printf '%s\n' "$ref_skills" | cut -f1)
    other_names=$(printf '%s\n' "$other_skills" | cut -f1)
    both=$(comm -12 <(echo "$ref_names") <(echo "$other_names") 2>/dev/null || true)
    only_ref=$(comm -23 <(echo "$ref_names") <(echo "$other_names") 2>/dev/null || true)
    only_other=$(comm -13 <(echo "$ref_names") <(echo "$other_names") 2>/dev/null || true)

    local item ref_path other_path
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      ref_path=$(printf '%s\n' "$ref_skills" | awk -F'\t' -v n="$item" '$1==n {print $2; exit}')
      other_path=$(printf '%s\n' "$other_skills" | awk -F'\t' -v n="$item" '$1==n {print $2; exit}')
      if [ -z "$ref_path" ]; then
        printf "  DRIFTED: %-29s (%s reference entry is a broken symlink — fix %s's copy first)\n" "$item" "$REFERENCE_AGENT" "$REFERENCE_AGENT"
        record_event "$WARNINGS_FILE" "DRIFTED" "skill" "$item" "$agent" "$REFERENCE_AGENT" "" "$REFERENCE_AGENT reference entry is a broken symlink"
      elif [ -z "$other_path" ]; then
        printf "  DRIFTED: %-29s (broken symlink)\n" "$item"
        printf "    fix: ln -sfn %s %s/%s\n" "$ref_path" "$other_dir" "$item"
        record_event "$WARNINGS_FILE" "DRIFTED" "skill" "$item" "$agent" "" "" "broken symlink"
      elif [ "$ref_path" != "$other_path" ]; then
        printf "  DRIFTED: %-29s (target differs: %s vs %s)\n" "$item" "$ref_path" "$other_path"
        printf "    fix: ln -sfn %s %s/%s\n" "$ref_path" "$other_dir" "$item"
        record_event "$WARNINGS_FILE" "DRIFTED" "skill" "$item" "$agent" "" "" "target differs: $ref_path vs $other_path"
      else
        printf "  %-40s both\n" "$item"
      fi
    done <<< "$both"

    while IFS= read -r item; do
      [ -z "$item" ] && continue
      local reason status
      set +e
      reason=$(accepted_gap_reason "skill" "$agent" "$REFERENCE_AGENT" "$item")
      status=$?
      set -e
      if [ "$status" -eq 2 ]; then
        local review_by base_reason
        base_reason="${reason#PAST-REVIEW|}"; base_reason="${base_reason%%|*}"
        review_by="${reason##*|}"
        printf "  PAST-REVIEW: %-25s (accepted exception past review date %s)\n" "$item" "$review_by"
        record_event "$WARNINGS_FILE" "PAST-REVIEW" "skill" "$item" "$agent" "$REFERENCE_AGENT" "$base_reason" "review_by=$review_by"
      elif [ "$status" -eq 0 ]; then
        printf "  ACCEPTED: %-29s %s only (%s)\n" "$item" "$REFERENCE_AGENT" "$reason"
        record_event "$ACCEPTED_FILE" "ACCEPTED" "skill" "$item" "$agent" "$REFERENCE_AGENT" "$reason"
      else
        ref_path=$(printf '%s\n' "$ref_skills" | awk -F'\t' -v n="$item" '$1==n {print $2; exit}')
        printf "  GAP: %-34s %s only\n" "$item" "$REFERENCE_AGENT"
        if [ -n "$ref_path" ]; then
          printf "    fix: ln -s %s %s/%s\n" "$ref_path" "$other_dir" "$item"
          record_event "$GAPS_FILE" "GAP" "skill" "$item" "$agent" "$REFERENCE_AGENT" "" "fix: ln -s $ref_path $other_dir/$item"
        else
          printf "    (no fix suggestion: %s reference entry is a broken symlink)\n" "$REFERENCE_AGENT"
          record_event "$GAPS_FILE" "GAP" "skill" "$item" "$agent" "$REFERENCE_AGENT" "" "$REFERENCE_AGENT reference entry is a broken symlink"
        fi
      fi
    done <<< "$only_ref"

    while IFS= read -r item; do
      [ -z "$item" ] && continue
      local reason status
      set +e
      reason=$(accepted_gap_reason "skill" "$agent" "$agent" "$item")
      status=$?
      set -e
      if [ "$status" -eq 2 ]; then
        local review_by base_reason
        base_reason="${reason#PAST-REVIEW|}"; base_reason="${base_reason%%|*}"
        review_by="${reason##*|}"
        printf "  PAST-REVIEW: %-25s (accepted exception past review date %s)\n" "$item" "$review_by"
        record_event "$WARNINGS_FILE" "PAST-REVIEW" "skill" "$item" "$agent" "$agent" "$base_reason" "review_by=$review_by"
      elif [ "$status" -eq 0 ]; then
        printf "  ACCEPTED: %-29s %s only (%s)\n" "$item" "$agent" "$reason"
        record_event "$ACCEPTED_FILE" "ACCEPTED" "skill" "$item" "$agent" "$agent" "$reason"
      else
        printf "  GAP: %-34s %s only\n" "$item" "$agent"
        record_event "$GAPS_FILE" "GAP" "skill" "$item" "$agent" "$agent"
      fi
    done <<< "$only_other"
  done
  echo ""
}

# --- Project scope ---
# Runs against $PWD (or AGENT_COMPAT_PROJECT_DIR). Axes: instructions + skills.
# Per-repo accepted gaps live in <project>/.agent-compat.json:
#   {"accepted_gaps": {"instructions": [{item, reason, review_by}], "skills": [...]}}
PROJECT_DIR="${AGENT_COMPAT_PROJECT_DIR:-$PWD}"
PROJECT_GAPS_FILE="$PROJECT_DIR/.agent-compat.json"

# Project-relative paths come from descriptors project_paths (per agent).
descriptor_project_path() {
  local agent="$1" key="$2" fallback="$3"
  jq -r --arg a "$agent" --arg k "$key" --arg f "$fallback" \
    '.agents[] | select(.name==$a) | .project_paths[$k] // $f' "$DESCRIPTORS"
}

project_accepted_reason() {
  local axis="$1" item="$2" entry reason review_by
  [ -f "$PROJECT_GAPS_FILE" ] || return 1
  entry=$(jq -c --arg axis "$axis" --arg item "$item" \
    '.accepted_gaps[$axis][]? | select(.item == $item or .item == "*")' "$PROJECT_GAPS_FILE" 2>/dev/null | head -1)
  [ -n "$entry" ] || return 1
  reason=$(echo "$entry" | jq -r '.reason')
  review_by=$(echo "$entry" | jq -r '.review_by // empty')
  if is_past_review "$review_by"; then
    echo "PAST-REVIEW|$reason|$review_by"
    return 2
  fi
  echo "$reason"
}

# Emits GAP/ACCEPTED/PAST-REVIEW for a project-scope item; suggestion printed
# on GAP when non-empty. Returns nothing; updates counters via record_event.
project_report_gap() {
  local axis="$1" item="$2" side="$3" suggestion="$4" reason status
  set +e
  reason=$(project_accepted_reason "$axis" "$item")
  status=$?
  set -e
  if [ "$status" -eq 2 ]; then
    local review_by base_reason
    base_reason="${reason#PAST-REVIEW|}"; base_reason="${base_reason%%|*}"
    review_by="${reason##*|}"
    printf "  PAST-REVIEW: %-25s (accepted exception past review date %s)\n" "$item" "$review_by"
    record_event "$WARNINGS_FILE" "PAST-REVIEW" "$axis" "$item" "project" "$side" "$base_reason" "review_by=$review_by"
  elif [ "$status" -eq 0 ]; then
    printf "  ACCEPTED: %-29s %s (%s)\n" "$item" "$side" "$reason"
    record_event "$ACCEPTED_FILE" "ACCEPTED" "$axis" "$item" "project" "$side" "$reason"
  else
    printf "  GAP: %-34s %s\n" "$item" "$side"
    [ -n "$suggestion" ] && printf "    fix: %s\n" "$suggestion"
    record_event "$GAPS_FILE" "GAP" "$axis" "$item" "project" "$side" "" "$suggestion"
  fi
}

# AGENTS.md is canonical. PASS = AGENTS.md exists AND CLAUDE.md is a symlink to
# it or begins with @AGENTS.md (Claude-specific sections may follow, never diffed).
check_project_instructions() {
  echo "instructions (project):"
  local agents_md claude_md
  agents_md="$PROJECT_DIR/$(descriptor_project_path opencode instructions AGENTS.md)"
  claude_md="$PROJECT_DIR/$(descriptor_project_path claude instructions CLAUDE.md)"

  if [ ! -e "$agents_md" ] && [ ! -e "$claude_md" ]; then
    echo "  (no project instructions — nothing to check)"
    echo ""
    return 0
  fi

  if [ ! -e "$agents_md" ]; then
    project_report_gap "instructions" "AGENTS.md" "missing (CLAUDE.md-only repo)" \
      "ln -s CLAUDE.md $agents_md   # or split: shared content to AGENTS.md, CLAUDE.md reduced to '@AGENTS.md' + Claude-specific remainder"
    echo ""
    return 0
  fi

  if [ ! -e "$claude_md" ]; then
    project_report_gap "instructions" "CLAUDE.md" "missing (AGENTS.md not imported for claude)" \
      "ln -s AGENTS.md $claude_md"
    echo ""
    return 0
  fi

  # Either direction of symlink counts: the two names resolving to the same
  # real file means every agent reads identical content.
  if [ "$(readlink -f "$claude_md" 2>/dev/null || true)" = "$(readlink -f "$agents_md" 2>/dev/null || true)" ]; then
    echo "  PASS: CLAUDE.md and AGENTS.md resolve to the same file"
  elif [ -L "$claude_md" ]; then
    project_report_gap "instructions" "CLAUDE.md" "symlink does not resolve to AGENTS.md" \
      "ln -sfn AGENTS.md $claude_md"
  elif [ "$(head -n 1 "$claude_md" 2>/dev/null)" = "@AGENTS.md" ]; then
    echo "  PASS: CLAUDE.md imports AGENTS.md (@AGENTS.md first line; Claude-specific remainder allowed)"
  else
    project_report_gap "instructions" "CLAUDE.md" "does not import AGENTS.md" \
      "make '@AGENTS.md' the first line of CLAUDE.md (Claude-specific sections may follow)"
  fi
  echo ""
}

# Every directory under .claude/skills/ must have a same-named entry under
# .opencode/skill/ resolving to it. Extra .opencode/skill entries are GAPs too.
check_project_skills() {
  echo "skills (project):"
  local claude_rel oc_rel claude_dir oc_dir oc_up
  claude_rel="$(descriptor_project_path claude skills .claude/skills)"
  oc_rel="$(descriptor_project_path opencode skills .opencode/skill)"
  claude_dir="$PROJECT_DIR/$claude_rel"
  oc_dir="$PROJECT_DIR/$oc_rel"
  # "../" per component of oc_rel, to build a relative symlink source
  oc_up="$(printf '%s\n' "$oc_rel" | awk -F/ '{for (i=1; i<=NF; i++) printf "../"}')"

  if [ ! -d "$claude_dir" ] && [ ! -d "$oc_dir" ]; then
    echo "  (no project skills — nothing to check)"
    echo ""
    return 0
  fi

  local name entry target
  if [ -d "$claude_dir" ]; then
    for entry in "$claude_dir"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      name="$(basename "$entry")"
      if [ ! -d "$entry" ]; then
        if [ -L "$entry" ] && [ ! -e "$entry" ]; then
          printf "  DRIFTED: %-29s (claude project entry is a broken symlink -> %s)\n" "$name" "$(readlink "$entry")"
          record_event "$WARNINGS_FILE" "DRIFTED" "skills" "$name" "project" "" "" "claude project entry is a broken symlink"
        fi
        continue
      fi
      if [ ! -e "$oc_dir/$name" ]; then
        project_report_gap "skills" "$name" "claude only (invisible to opencode)" \
          "mkdir -p $oc_dir && ln -s ${oc_up}${claude_rel}/$name $oc_dir/$name"
      else
        target="$(readlink -f "$oc_dir/$name" 2>/dev/null || true)"
        if [ "$target" = "$(readlink -f "$claude_dir/$name")" ]; then
          printf "  %-40s both\n" "$name"
        else
          printf "  DRIFTED: %-29s (opencode entry does not resolve to %s/%s)\n" "$name" "$claude_rel" "$name"
          printf "    fix: ln -sfn %s%s/%s %s/%s\n" "$oc_up" "$claude_rel" "$name" "$oc_dir" "$name"
          record_event "$WARNINGS_FILE" "DRIFTED" "skills" "$name" "project" "" "" "opencode entry resolves elsewhere"
        fi
      fi
    done
  fi
  if [ -d "$oc_dir" ]; then
    for entry in "$oc_dir"/*/; do
      [ -e "$entry" ] || continue
      name="$(basename "$entry")"
      [ -e "$claude_dir/$name" ] && continue
      project_report_gap "skills" "$name" "opencode only (invisible to claude)" \
        "mkdir -p $claude_dir && ln -s $oc_dir/$name $claude_dir/$name"
    done
  fi
  echo ""
}

run_project_report() {
  echo "agent-compat (project scope): $PROJECT_DIR"
  echo ""
  case "$AXIS" in
    all)          check_project_instructions; check_project_skills ;;
    instructions) check_project_instructions ;;
    skills)       check_project_skills ;;
    *)
      echo "axis '$AXIS' is global-only; project scope checks instructions + skills (skipped)"
      return 0
      ;;
  esac
}

run_report() {
  echo "agent-compat: $AGENT_COUNT agent(s) detected ($(echo $INSTALLED | tr '\n' ' ' | sed 's/ $//'))"
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
    all)               check_permissions; check_model; check_instructions; check_hooks; check_agent_definitions; check_skills ;;
    permissions)       check_permissions ;;
    model)             check_model ;;
    instructions)      check_instructions ;;
    hooks)             check_hooks ;;
    agent-definitions) check_agent_definitions ;;
    skills)            check_skills ;;
  esac
}

set +e
if [ "$SCOPE" = "project" ]; then
  PROSE_OUTPUT="$(run_project_report)"
else
  PROSE_OUTPUT="$(run_report)"
fi
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
