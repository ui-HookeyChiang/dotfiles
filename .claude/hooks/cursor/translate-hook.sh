#!/usr/bin/env bash
# translate-hook.sh — run a Claude Code hook script and translate its output
# to the Cursor hook format.
#
# Claude Code hooks output:
#   {"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "..."}}
#
# Cursor hooks output:
#   {"permission": "deny", "user_message": "..."}
#
# Usage: translate-hook.sh <hook-script> [args...]
set -uo pipefail

HOOK_SCRIPT="$1"
shift

INPUT="$(cat)"

OUTPUT="$(printf '%s' "$INPUT" | bash "$HOOK_SCRIPT" "$@")"
EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  exit "$EXIT_CODE"
fi

if [ -z "$OUTPUT" ]; then
  exit 0
fi

DECISION="$(printf '%s' "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"

if [ "$DECISION" = "deny" ]; then
  REASON="$(printf '%s' "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // "Blocked by hook"' 2>/dev/null)"
  jq -n --arg r "$REASON" '{"permission": "deny", "user_message": $r}'
  exit 0
fi

if [ "$DECISION" = "allow" ]; then
  REASON="$(printf '%s' "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)"
  if [ -n "$REASON" ]; then
    jq -n --arg r "$REASON" '{"permission": "allow", "user_message": $r}'
  else
    jq -n '{"permission": "allow"}'
  fi
  exit 0
fi

exit 0
