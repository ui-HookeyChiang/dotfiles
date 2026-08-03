#!/usr/bin/env bash
# Verify descriptor-driven detection and accepted gap reporting.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARITY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO_ROOT="$(cd "$PARITY_ROOT/.." && pwd)"
FAKE_HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.claude/agents" "$FAKE_HOME/.cursor" "$FAKE_HOME/.cursor/agents" "$FAKE_BIN"
printf '#!/usr/bin/env bash
exit 0
' > "$FAKE_BIN/claude"
chmod +x "$FAKE_BIN/claude"

printf '%s
' '{"model":"claude-opus-4-6[1m]","hooks":{"PreToolUse":[{"hooks":[{"command":"bash ~/.claude/hooks/block-main-edit.sh"}]}],"SessionStart":[{"hooks":[{"command":"bash ~/.claude/hooks/check-parity-session.sh"}]}],"SubagentStart":[{"hooks":[{"command":"bash ~/.claude/hooks/subagent-dispatch-inject.sh"}]}]}}' > "$FAKE_HOME/.claude/settings.json"
printf '%s
' '{"model":{"displayModelId":"cursor-model"},"hooks":{"preToolUse":[{"command":"bash ~/.claude/hooks/block-main-edit.sh"}]}}' > "$FAKE_HOME/.cursor/cli-config.json"
printf '%s
' '{"hooks":{"preToolUse":[{"command":"bash ~/.claude/hooks/block-main-edit.sh"}]}}' > "$FAKE_HOME/.cursor/hooks.json"
for agent in decide execute execute-deep execute-review scan scan-search; do
  ln -s "$REPO_ROOT/docs/agent-definitions/$agent.md" "$FAKE_HOME/.claude/agents/$agent.md"
  ln -s "$REPO_ROOT/.cursor/agents/$agent.md" "$FAKE_HOME/.cursor/agents/$agent.md"
done

DETECTED="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" "$PARITY_ROOT/scripts/detect-agents.sh")"
if ! echo "$DETECTED" | jq -e '.agents[] | select(.name=="cursor" and .installed==true and (.settings | endswith(".cursor/cli-config.json")))' >/dev/null; then
  echo "FAIL: cursor descriptor detection did not report expected settings path" >&2
  echo "$DETECTED" >&2
  exit 1
fi
if ! echo "$DETECTED" | jq -e '.agents[] | select(.name=="cursor" and .installed==true and (.agent_definitions | endswith(".cursor/agents")))' >/dev/null; then
  echo "FAIL: cursor descriptor detection did not report expected agent definitions path" >&2
  echo "$DETECTED" >&2
  exit 1
fi

AGENT_OUTPUT="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" "$PARITY_ROOT/scripts/check-parity.sh" --axis agent-definitions --agent cursor)"
if echo "$AGENT_OUTPUT" | rg -q 'GAP:|DRIFTED|DIVERGED'; then
  echo "FAIL: cursor agent-definition parity should have no unaccepted gaps or drift" >&2
  echo "$AGENT_OUTPUT" >&2
  exit 1
fi
for accepted in decide execute-deep; do
  if ! echo "$AGENT_OUTPUT" | rg -q "ACCEPTED: +$accepted"; then
    echo "FAIL: missing accepted exception for $accepted" >&2
    echo "$AGENT_OUTPUT" >&2
    exit 1
  fi
done
if ! echo "$AGENT_OUTPUT" | rg -q 'summary: 0 gap\(s\), 0 warning\(s\), 2 accepted exception\(s\)'; then
  echo "FAIL: unexpected cursor agent-definition parity summary" >&2
  echo "$AGENT_OUTPUT" >&2
  exit 1
fi

OUTPUT="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" "$PARITY_ROOT/scripts/check-parity.sh" --axis hooks --agent cursor)"
if ! echo "$OUTPUT" | rg -q 'ACCEPTED: check-parity-session'; then
  echo "FAIL: descriptor accepted gap not reported" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
if ! echo "$OUTPUT" | rg -q 'summary: 0 gap\(s\), 0 warning\(s\), 2 accepted exception\(s\)'; then
  echo "FAIL: descriptor accepted gaps did not keep hook parity green" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

JSON_OUTPUT="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" "$PARITY_ROOT/scripts/check-parity.sh" --format json --axis hooks --agent cursor)"
if ! echo "$JSON_OUTPUT" | jq -e '.counts == {gaps: 0, warnings: 0, accepted: 2} and (.gaps | length == 0) and (.warnings | length == 0) and (.accepted | length == 2)' >/dev/null; then
  echo "FAIL: clean JSON output did not report expected structure/counts" >&2
  echo "$JSON_OUTPUT" >&2
  exit 1
fi

printf '%s
' '{"hooks":{"preToolUse":[{"command":"bash ~/.claude/hooks/block-main-edit.sh"},{"command":"bash ~/.claude/hooks/extra-local-only.sh"}]}}' > "$FAKE_HOME/.cursor/hooks.json"
set +e
DRIFT_JSON="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" "$PARITY_ROOT/scripts/check-parity.sh" --format json --axis hooks --agent cursor)"
DRIFT_STATUS=$?
set -e
if [ "$DRIFT_STATUS" -ne 1 ]; then
  echo "FAIL: drifted JSON fixture exited $DRIFT_STATUS, expected 1" >&2
  echo "$DRIFT_JSON" >&2
  exit 1
fi
if ! echo "$DRIFT_JSON" | jq -e '.counts.gaps == 1 and .counts.warnings == 0 and (.gaps[] | select(.kind=="GAP" and .item=="extra-local-only" and .side=="cursor"))' >/dev/null; then
  echo "FAIL: drifted JSON fixture did not report expected GAP" >&2
  echo "$DRIFT_JSON" >&2
  exit 1
fi
HOOK_OUTPUT="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" "$PARITY_ROOT/../hooks/check-parity-session.sh")"
if ! echo "$HOOK_OUTPUT" | rg -q 'GAP: extra-local-only'; then
  echo "FAIL: session hook banner did not include JSON GAP item" >&2
  echo "$HOOK_OUTPUT" >&2
  exit 1
fi
if ! echo "$HOOK_OUTPUT" | rg -q 'ACCEPTED: check-parity-session'; then
  echo "FAIL: session hook banner did not include JSON ACCEPTED item" >&2
  echo "$HOOK_OUTPUT" >&2
  exit 1
fi

set +e
HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" "$PARITY_ROOT/scripts/check-parity.sh" --format xml >/dev/null 2>&1
USAGE_STATUS=$?
set -e
if [ "$USAGE_STATUS" -ne 2 ]; then
  echo "FAIL: invalid format exited $USAGE_STATUS, expected 2" >&2
  exit 1
fi

echo "PASS: agent parity descriptors drive detection, accepted gaps, and structured output"
