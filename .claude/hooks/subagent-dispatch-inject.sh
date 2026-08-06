#!/usr/bin/env bash
# SubagentStart hook: inject failure escalation + red lines into subagents,
# and record agent_id → worktree mapping for guard-agent-worktree.sh.

_SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")" 2>/dev/null || echo "$(dirname "$0")")"
_SHARED_LIB="${_SCRIPT_DIR}/../_shared/lib/sh/portability.sh"
[ -f "$_SHARED_LIB" ] && source "$_SHARED_LIB" || true

input="$(cat)"

# --- Agent-map: record assigned worktree for isolation guard ---
agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)"
prompt="$(printf '%s' "$input" | jq -r '.subagent_prompt // empty' 2>/dev/null)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

if [ -n "$agent_id" ] && [ -n "$prompt" ] && [ -n "$PROJECT_DIR" ]; then
  worktree=""
  if [[ "$prompt" =~ \.worktrees/[^[:space:]\"\']+ ]]; then
    candidate="${BASH_REMATCH[0]}"
    candidate="${candidate%%\"*}"
    candidate="${candidate%%\'*}"
    candidate="${candidate%%\`*}"
    case "$candidate" in
      /*) abs="$candidate" ;;
      *)  abs="$PROJECT_DIR/$candidate" ;;
    esac
    worktree="$(portable_realpath_m "$abs" 2>/dev/null || echo "$abs")"
  fi
  if [ -n "$worktree" ]; then
    map_dir="$PROJECT_DIR/.worktrees/.agent-map"
    mkdir -p "$map_dir"
    printf '%s' "$worktree" > "$map_dir/$agent_id"
  fi
fi

# Single source for the injected rules — shared with install.sh, which bakes
# the same block into OpenCode agent definitions (no SubagentStart surface there).
RULES_FILE="$(dirname "$(readlink -f "$0")")/subagent-red-lines.md"
[ -f "$RULES_FILE" ] || exit 0
RULES="$(cat "$RULES_FILE")"

jq -nc --arg c "$RULES" '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$c}}'
