#!/usr/bin/env bash
# Verify check-parity.sh downgrades a past-due accepted_gaps/accepted_model_reason
# exception to a WARNING (PAST-REVIEW) instead of silently counting ACCEPTED.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARITY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.cursor" "$FAKE_BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/claude"
chmod +x "$FAKE_BIN/claude"

printf '%s\n' '{"model":"claude-opus-4-6","hooks":{"SessionStart":[{"hooks":[{"command":"bash ~/.claude/hooks/check-parity-session.sh"}]}]}}' > "$FAKE_HOME/.claude/settings.json"
printf '%s\n' '{"model":{"displayModelId":"gpt-5.5"},"hooks":{}}' > "$FAKE_HOME/.cursor/cli-config.json"
printf '{}\n' > "$FAKE_HOME/.cursor/hooks.json"

FAKE_DESCRIPTORS="$TMP_ROOT/agents.json"
jq -n '{
  agents: [
    {name:"claude", detection:{probes:[{type:"command",value:"claude"}]}, paths:{settings:"~/.claude/settings.json", instructions:"", hooks:"~/.claude/hooks"}},
    {name:"cursor", detection:{probes:[{type:"dir",value:"~/.cursor"}]}, paths:{settings:"~/.cursor/cli-config.json", instructions:"", hooks:"~/.cursor/hooks.json"},
     accepted_model_reason:"Cursor active model is a documented local exception",
     accepted_model_review_by:"2020-01-01",
     accepted_gaps:{hook:{claude:[{item:"check-parity-session", reason:"past-due test fixture", review_by:"2020-01-01"}]}}}
  ]
}' > "$FAKE_DESCRIPTORS"

set +e
OUTPUT="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" AGENT_PARITY_DESCRIPTORS="$FAKE_DESCRIPTORS" "$PARITY_ROOT/scripts/check-parity.sh" --axis hooks --agent cursor)"
set -e
if ! echo "$OUTPUT" | grep -q 'PAST-REVIEW: check-parity-session.*accepted exception past review date 2020-01-01'; then
  echo "FAIL: expected PAST-REVIEW warning for past-due hook accepted_gaps entry" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
if echo "$OUTPUT" | grep -q 'ACCEPTED: check-parity-session'; then
  echo "FAIL: past-due entry should not be counted ACCEPTED" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

set +e
MODEL_OUTPUT="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" AGENT_PARITY_DESCRIPTORS="$FAKE_DESCRIPTORS" "$PARITY_ROOT/scripts/check-parity.sh" --axis model --agent cursor)"
set -e
if ! echo "$MODEL_OUTPUT" | grep -q 'PAST-REVIEW: model.*accepted exception past review date 2020-01-01'; then
  echo "FAIL: expected PAST-REVIEW warning for past-due accepted_model_reason" >&2
  echo "$MODEL_OUTPUT" >&2
  exit 1
fi

set +e
HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" AGENT_PARITY_DESCRIPTORS="$FAKE_DESCRIPTORS" \
  "$PARITY_ROOT/scripts/check-parity.sh" --format json --axis hooks --agent cursor > "$TMP_ROOT/json.out"
JSON_STATUS=$?
set -e
if [ "$JSON_STATUS" -ne 1 ]; then
  echo "FAIL: past-due warning should exit 1 (like other warnings), got $JSON_STATUS" >&2
  cat "$TMP_ROOT/json.out" >&2
  exit 1
fi
jq -e '.counts.warnings >= 1 and (.warnings[] | select(.kind=="PAST-REVIEW" and .item=="check-parity-session"))' "$TMP_ROOT/json.out" >/dev/null || {
  echo "FAIL: JSON output missing PAST-REVIEW warning entry" >&2
  cat "$TMP_ROOT/json.out" >&2
  exit 1
}

echo "PASS: check-parity.sh downgrades past-due accepted exceptions to PAST-REVIEW warnings"
