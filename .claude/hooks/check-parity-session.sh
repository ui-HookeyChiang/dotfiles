#!/usr/bin/env bash
# SessionStart hook: lightweight parity check across agents.
# Runs check-parity.sh in quick mode — hash comparison only, no full diff.
# If drift detected, emits system-reminder so agent can offer to fix.
set -euo pipefail

PARITY_SCRIPT=""

# Find check-parity.sh — installed skill, then co-located repo (via hook symlink)
HOOK_REAL="$(readlink -f "$0" 2>/dev/null || echo "$0")"
HOOK_REPO="$(cd "$(dirname "$HOOK_REAL")/.." 2>/dev/null && pwd)"
for candidate in \
  "$HOME/.claude/skills/agent-parity/scripts/check-parity.sh" \
  "$HOOK_REPO/agent-parity/scripts/check-parity.sh"; do
  [ -x "$candidate" ] && { PARITY_SCRIPT="$candidate"; break; }
done

# No parity script found — silent exit
[ -n "$PARITY_SCRIPT" ] || exit 0

# Detect agents — need 2+ to compare
DETECT_SCRIPT="$(dirname "$PARITY_SCRIPT")/detect-agents.sh"
[ -x "$DETECT_SCRIPT" ] || exit 0

AGENT_COUNT=$("$DETECT_SCRIPT" 2>/dev/null | jq '[.agents[] | select(.installed)] | length' 2>/dev/null || echo 0)
[ "$AGENT_COUNT" -ge 2 ] || exit 0

# Run parity check, capture output
output=$("$PARITY_SCRIPT" 2>/dev/null || true)
gaps=$(echo "$output" | sed -n 's/.*\([0-9]\+\) gap.*/\1/p' | tail -1)
warnings=$(echo "$output" | sed -n 's/.*\([0-9]\+\) warning.*/\1/p' | tail -1)
gaps="${gaps:-0}"
warnings="${warnings:-0}"

# No drift — silent
[ "$gaps" -eq 0 ] && [ "$warnings" -eq 0 ] && exit 0

# Drift detected — emit condensed summary
drift_lines=$(echo "$output" | sed -n '/MISSING\|DRIFTED\|UNDECLARED\|DIVERGED/p')

echo "Agent parity drift detected ($gaps gap(s), $warnings warning(s)). Run /agent-parity for details. Divergences:"
echo "$drift_lines"
