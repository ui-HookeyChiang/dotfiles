#!/usr/bin/env bash
# check-parity.sh — runtime parity diff across detected agents.
# Compares actual config from both agents — no manifest needed.
# Reports: GAP (one side has it, other doesn't), DRIFTED (both have it, content differs).
# Usage: check-parity.sh [--axis permissions|model|instructions|hooks|all]
set -euo pipefail

AXIS="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --axis) AXIS="${2:-all}"; shift 2 ;;
    --axis=*) AXIS="${1#--axis=}"; shift ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAPS=0
WARNINGS=0

# --- Agent detection ---
AGENTS_JSON="$("$SCRIPT_DIR/detect-agents.sh")"
INSTALLED=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.installed) | .name')
AGENT_COUNT=$(echo "$INSTALLED" | wc -w)

echo "agent-parity: $AGENT_COUNT agent(s) detected ($(echo $INSTALLED | tr '\n' ' ' | sed 's/ $//'))"
echo ""

if [ "$AGENT_COUNT" -lt 2 ]; then
  echo "Need at least 2 installed agents to compare."
  exit 0
fi

# --- Helper: extract agent config ---
get_claude_denies() {
  local settings
  settings=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="claude") | .settings')
  [ -n "$settings" ] && [ -f "$settings" ] || return
  jq -r '.permissions.deny[]?' "$settings" 2>/dev/null | sed 's/Bash(//;s/)$//;s/:\*$//;s/ \*$//' | sort -u
}

get_opencode_denies() {
  local settings
  settings=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="opencode") | .settings')
  [ -n "$settings" ] && [ -f "$settings" ] || return
  jq -r '.permission.bash | to_entries[] | select(.value=="deny") | .key' "$settings" 2>/dev/null \
    | sed 's/ \*$//' | sort -u
}

get_claude_docs() {
  local instr real_instr
  instr=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="claude") | .instructions')
  [ -n "$instr" ] && [ -f "$instr" ] || return
  real_instr="$instr"
  [ -L "$real_instr" ] && real_instr="$(readlink -f "$real_instr")"
  rg '^@' "$real_instr" 2>/dev/null | sed 's/^@//;s|.*/||' | sort
}

get_opencode_docs() {
  local settings
  settings=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="opencode") | .settings')
  [ -n "$settings" ] && [ -f "$settings" ] || return
  jq -r '.instructions[]?' "$settings" 2>/dev/null | sed 's|.*/||' | sort
}

get_claude_hooks() {
  local settings
  settings=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="claude") | .settings')
  [ -n "$settings" ] && [ -f "$settings" ] || return
  jq -r '[.hooks[]?[]?.hooks[]?.command // empty] | .[]' "$settings" 2>/dev/null \
    | sed 's|.*/||;s/\.sh$//;s/^rtk hook claude$/rtk/;s/^bash //' | sort -u
}

get_opencode_hooks() {
  local hooks_dir
  hooks_dir=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="opencode") | .hooks')
  [ -n "$hooks_dir" ] && [ -d "$hooks_dir" ] || return
  ls "$hooks_dir"/*.js "$hooks_dir"/*.ts 2>/dev/null \
    | xargs -I{} basename {} | sed 's/\.\(js\|ts\)$//' | sort -u
  local agents_dir
  agents_dir="$(dirname "$hooks_dir")/agents"
  if [ -d "$agents_dir" ]; then
    rg -ql 'Delivery Red Lines' "$agents_dir"/*.md 2>/dev/null && echo "subagent-dispatch-inject"
  fi
}

resolve_doc_path() {
  local agent="$1" doc="$2"
  case "$agent" in
    claude)
      local claude_instr
      claude_instr=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="claude") | .instructions')
      [ -n "$claude_instr" ] && [ -f "$claude_instr" ] || return
      local base_dir
      base_dir="$(dirname "$(readlink -f "$claude_instr")")"
      local ref
      ref=$(rg "^@.*${doc}$" "$(readlink -f "$claude_instr")" 2>/dev/null | head -1 | sed 's/^@//')
      [ -n "$ref" ] && echo "$base_dir/$ref"
      ;;
    opencode)
      local oc_settings
      oc_settings=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="opencode") | .settings')
      [ -n "$oc_settings" ] && [ -f "$oc_settings" ] || return
      local path
      path=$(jq -r ".instructions[]? | select(endswith(\"$doc\"))" "$oc_settings" 2>/dev/null | head -1)
      [ -n "$path" ] && eval echo "$path"
      ;;
  esac
}

# --- Diff helper: compare two sorted lists ---
# Reports items in both, only-claude, only-opencode
diff_lists() {
  local label="$1"
  local claude_list="$2"
  local opencode_list="$3"
  local check_content="${4:-no}"

  local both only_claude only_opencode
  both=$(comm -12 <(echo "$claude_list") <(echo "$opencode_list") 2>/dev/null || true)
  only_claude=$(comm -23 <(echo "$claude_list") <(echo "$opencode_list") 2>/dev/null || true)
  only_opencode=$(comm -13 <(echo "$claude_list") <(echo "$opencode_list") 2>/dev/null || true)

  while IFS= read -r item; do
    [ -z "$item" ] && continue
    if [ "$check_content" = "yes" ]; then
      local c_path oc_path
      c_path=$(resolve_doc_path claude "$item")
      oc_path=$(resolve_doc_path opencode "$item")
      if [ -n "$c_path" ] && [ -f "$c_path" ] && [ -n "$oc_path" ] && [ -f "$oc_path" ]; then
        if ! diff -q "$c_path" "$oc_path" >/dev/null 2>&1; then
          printf "  DRIFTED: %-29s (content differs)\n" "$item"
          WARNINGS=$((WARNINGS + 1))
          continue
        fi
      fi
    fi
    printf "  %-40s both\n" "$item"
  done <<< "$both"

  while IFS= read -r item; do
    [ -z "$item" ] && continue
    printf "  GAP: %-34s claude only\n" "$item"
    GAPS=$((GAPS + 1))
  done <<< "$only_claude"

  while IFS= read -r item; do
    [ -z "$item" ] && continue
    printf "  GAP: %-34s opencode only\n" "$item"
    GAPS=$((GAPS + 1))
  done <<< "$only_opencode"
}

# --- Permissions axis ---
check_permissions() {
  echo "permissions:"
  local claude_denies opencode_denies
  claude_denies=$(get_claude_denies | sort)
  opencode_denies=$(get_opencode_denies | sort)
  diff_lists "deny" "$claude_denies" "$opencode_denies"
  echo ""
}

# --- Model axis ---
check_model() {
  echo "model:"
  local claude_settings oc_settings claude_model oc_model
  claude_settings=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="claude") | .settings')
  oc_settings=$(echo "$AGENTS_JSON" | jq -r '.agents[] | select(.name=="opencode") | .settings')

  claude_model=""; oc_model=""
  [ -n "$claude_settings" ] && [ -f "$claude_settings" ] && claude_model=$(jq -r '.model // empty' "$claude_settings" 2>/dev/null)
  [ -n "$oc_settings" ] && [ -f "$oc_settings" ] && oc_model=$(jq -r '.model // empty' "$oc_settings" 2>/dev/null)

  printf "  claude: %s\n" "${claude_model:-not set}"
  printf "  opencode: %s\n" "${oc_model:-not set}"

  local claude_base oc_base
  claude_base=$(echo "$claude_model" | sed 's/\[.*\]//;s/^.*\///;s/\./-/g')
  oc_base=$(echo "$oc_model" | sed 's/\[.*\]//;s/^.*\///;s/\./-/g')

  if [ "$claude_base" = "$oc_base" ]; then
    echo "  MATCH (same base model)"
  else
    echo "  DIVERGED (different base model)"
    GAPS=$((GAPS + 1))
  fi
  echo ""
}

# --- Instructions axis ---
check_instructions() {
  echo "instructions:"
  local claude_docs opencode_docs
  claude_docs=$(get_claude_docs | sort)
  opencode_docs=$(get_opencode_docs | sort)
  diff_lists "doc" "$claude_docs" "$opencode_docs" "yes"
  echo ""
}

# --- Hooks axis ---
check_hooks() {
  echo "hooks:"
  local claude_hooks opencode_hooks
  claude_hooks=$(get_claude_hooks | sort)
  opencode_hooks=$(get_opencode_hooks | sort)
  diff_lists "hook" "$claude_hooks" "$opencode_hooks"
  echo ""
}

# --- Run ---
case "$AXIS" in
  all)          check_permissions; check_model; check_instructions; check_hooks ;;
  permissions)  check_permissions ;;
  model)        check_model ;;
  instructions) check_instructions ;;
  hooks)        check_hooks ;;
  *) echo "Unknown axis: $AXIS (valid: permissions, model, instructions, hooks, all)"; exit 1 ;;
esac

echo "summary: $GAPS gap(s), $WARNINGS warning(s)"
exit 0
