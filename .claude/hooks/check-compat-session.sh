#!/usr/bin/env bash
# SessionStart hook: lightweight compatibility check across agents.
# Runs check-compat.sh in quick mode — hash comparison only, no full diff.
# If drift detected, emits system-reminder so agent can offer to fix.
set -euo pipefail

COMPAT_SCRIPT=""

# Find check-compat.sh — installed skill, then co-located repo (via hook symlink)
HOOK_REAL="$(readlink -f "$0" 2>/dev/null || echo "$0")"
HOOK_REPO="$(cd "$(dirname "$HOOK_REAL")/.." 2>/dev/null && pwd)"
for candidate in \
  "$HOME/.claude/skills/agent-compat/scripts/check-compat.sh" \
  "$HOOK_REPO/agent-compat/scripts/check-compat.sh"; do
  [ -x "$candidate" ] && { COMPAT_SCRIPT="$candidate"; break; }
done

# No compatibility script found — silent exit
[ -n "$COMPAT_SCRIPT" ] || exit 0

# Run compatibility check once; check-compat owns detection and comparability gates.
set +e
output=$("$COMPAT_SCRIPT" --format json 2>/dev/null)
status=$?
set -e
[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || exit 0

gaps=$(echo "$output" | jq -r '.counts.gaps // 0' 2>/dev/null || echo 0)
warnings=$(echo "$output" | jq -r '.counts.warnings // 0' 2>/dev/null || echo 0)

# No drift — silent
[ "$gaps" -eq 0 ] && [ "$warnings" -eq 0 ] && exit 0

# Drift detected — emit condensed summary
drift_lines=$(echo "$output" | jq -r '
  def side_text: if .side then " \(.side) only" else "" end;
  def detail_text: if .detail then " (\(.detail))" else "" end;
  def reason_text: if .reason then " (\(.reason))" else "" end;
  (.gaps[]?, .warnings[]?, .accepted[]?)
  | if .kind == "ACCEPTED" then
      "  ACCEPTED: \(.item)\(side_text)\(reason_text)"
    elif .kind == "DRIFTED" then
      "  DRIFTED: \(.item)\(detail_text)"
    elif .kind == "DIVERGED" then
      "  DIVERGED: \(.item)\(detail_text)"
    else
      "  GAP: \(.item)\(side_text)"
    end
' 2>/dev/null || true)

echo "Agent compatibility drift detected ($gaps gap(s), $warnings warning(s)). Run /agent-compat for details. Divergences:"
echo "$drift_lines"
