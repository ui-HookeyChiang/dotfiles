#!/usr/bin/env bash
# Verify register-harness uses descriptor detection across all agent harnesses.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.codex" "$FAKE_HOME/.cursor" "$FAKE_HOME/.config/opencode" "$FAKE_BIN"
printf '{}
' > "$FAKE_HOME/.claude/settings.json"
printf '{"hooks":{"PreToolUse":[]}}
' > "$FAKE_HOME/.codex/hooks.json"
printf '{"version":1,"hooks":{"preToolUse":[]}}
' > "$FAKE_HOME/.cursor/hooks.json"
printf '{}
' > "$FAKE_HOME/.config/opencode/opencode.json"

for bin in claude codex cursor opencode; do
  printf '#!/usr/bin/env bash
exit 0
' > "$FAKE_BIN/$bin"
  chmod +x "$FAKE_BIN/$bin"
done

HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" bash "$REPO_ROOT/scripts/register-harness.sh" --all --configure-hooks >/dev/null

jq -e '(.hooks.PreToolUse | length) == 6 and (.hooks.SubagentStart | length) == 1' "$FAKE_HOME/.claude/settings.json" >/dev/null
jq -e '(.hooks.PreToolUse | length) == 5 and (.hooks.SubagentStart | length) == 1' "$FAKE_HOME/.codex/hooks.json" >/dev/null
jq -e '(.hooks.preToolUse | length) == 5' "$FAKE_HOME/.cursor/hooks.json" >/dev/null

HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" bash "$REPO_ROOT/scripts/register-harness.sh" --all --configure-hooks --dry-run >/dev/null

echo "PASS: register-harness detects all fixture agent harnesses and configures hooks"
