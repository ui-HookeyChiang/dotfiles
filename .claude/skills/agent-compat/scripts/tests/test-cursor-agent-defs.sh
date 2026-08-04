#!/usr/bin/env bash
# Verify cursor extractor surfaces the descriptor-configured agents dir as
# agent-definitions,
# comparing (not skipping) against claude, with real per-item gaps/accepts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPAT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_HOME/.claude/agents" "$FAKE_HOME/.cursor/agents" "$FAKE_BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/claude"
chmod +x "$FAKE_BIN/claude"

printf '{}\n' > "$FAKE_HOME/.claude/settings.json"
printf '{}\n' > "$FAKE_HOME/.cursor/cli-config.json"

: > "$FAKE_HOME/.claude/agents/scan.md"
: > "$FAKE_HOME/.claude/agents/execute.md"
: > "$FAKE_HOME/.claude/agents/decide.md"

# cursor only has scan + a cursor-only extra; execute/decide are gaps
: > "$FAKE_HOME/.cursor/agents/scan.md"
: > "$FAKE_HOME/.cursor/agents/cursor-only.md"

# Fixture descriptors: point cursor agent_definitions at the fixture dir and
# drop cursor's agent-definition accepted_gaps so raw GAP reporting is tested.
FIXTURE_DESCRIPTORS="$TMP_ROOT/agents.json"
jq --arg dir "$FAKE_HOME/.cursor/agents" '
  (.agents[] | select(.name=="cursor") | .paths.agent_definitions) = $dir
  | (.agents[] | select(.name=="cursor") | .accepted_gaps["agent-definition"]) = {}
' "$COMPAT_ROOT/descriptors/agents.json" > "$FIXTURE_DESCRIPTORS"

set +e
OUTPUT="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" AGENT_COMPAT_DESCRIPTORS="$FIXTURE_DESCRIPTORS" "$COMPAT_ROOT/scripts/check-compat.sh" --axis agent-definitions --agent cursor)"
set -e

echo "$OUTPUT" | grep -q '  scan .*both' || {
  echo "FAIL: expected scan to match as 'both'" >&2
  echo "$OUTPUT" >&2
  exit 1
}
echo "$OUTPUT" | grep -q 'GAP: execute .*claude only' || {
  echo "FAIL: expected execute GAP (claude only)" >&2
  echo "$OUTPUT" >&2
  exit 1
}
echo "$OUTPUT" | grep -q 'GAP: decide .*claude only' || {
  echo "FAIL: expected decide GAP (claude only)" >&2
  echo "$OUTPUT" >&2
  exit 1
}
echo "$OUTPUT" | grep -q 'GAP: cursor-only .*cursor only' || {
  echo "FAIL: expected cursor-only GAP (cursor only)" >&2
  echo "$OUTPUT" >&2
  exit 1
}
# Must NOT be accepted/skipped — the stale accepted_gaps entries were removed.
if echo "$OUTPUT" | grep -q 'ACCEPTED.*execute\|ACCEPTED.*decide\|ACCEPTED.*scan'; then
  echo "FAIL: agent-definition gaps should no longer be silently accepted" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

echo "PASS: cursor agent-defs extraction reads the configured agents dir and reports real gaps"
