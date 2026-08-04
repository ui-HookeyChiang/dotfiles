#!/usr/bin/env bash
# test-cursor-translate-hook.sh — tests for cursor translate-hook.sh bridge
#
# Tests the translation from Claude Code hook output to Cursor hook format.
# Feeds payloads through translate-hook.sh wrapping block-bare-read.sh and
# block-heredoc-continuation.sh to verify:
#   - Deny cases emit Cursor JSON with permission: "deny"
#   - Allow cases (explicit allow in hook) emit Cursor JSON with permission: "allow"
#   - Empty hook output passes through (no JSON)
#   - Stderr is forwarded/visible to the caller
#
set -eo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRANSLATE_HOOK="$HOOKS_DIR/cursor/translate-hook.sh"
BLOCK_BARE_READ="$HOOKS_DIR/block-bare-read.sh"
BLOCK_HEREDOC="$HOOKS_DIR/block-heredoc-continuation.sh"

PASS_COUNT=0
FAIL_COUNT=0

# Helper: assert deny
assert_denied() {
  local payload="$1" expected_reason="$2" hook="$3" test_name="$4"
  local output

  output=$(bash "$TRANSLATE_HOOK" "$hook" <<< "$payload" 2>/dev/null || true)

  local permission=$(printf '%s' "$output" | jq -r '.permission // empty' 2>/dev/null || true)
  if [ "$permission" != "deny" ]; then
    echo "FAIL [$test_name]: Expected deny, got: $output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  local reason=$(printf '%s' "$output" | jq -r '.user_message // empty' 2>/dev/null || true)
  if [[ ! "$reason" =~ $expected_reason ]]; then
    echo "FAIL [$test_name]: Expected reason to contain '$expected_reason', got: $reason"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  echo "PASS [$test_name]: Denied with correct reason"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# Helper: assert empty/pass-through
assert_passthrough() {
  local payload="$1" hook="$2" test_name="$3"
  local output

  output=$(bash "$TRANSLATE_HOOK" "$hook" <<< "$payload" 2>/dev/null || true)

  if [ -n "$output" ]; then
    echo "FAIL [$test_name]: Expected empty output (pass-through), got: $output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  echo "PASS [$test_name]: Passed through (empty output)"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# Helper: assert explicit allow
assert_allowed() {
  local payload="$1" hook="$2" test_name="$3"
  local output

  output=$(bash "$TRANSLATE_HOOK" "$hook" <<< "$payload" 2>/dev/null || true)

  # Should have permission: allow
  if [ -z "$output" ]; then
    echo "FAIL [$test_name]: Expected allow output, got empty"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  local permission=$(printf '%s' "$output" | jq -r '.permission // empty' 2>/dev/null || true)
  if [ "$permission" != "allow" ]; then
    echo "FAIL [$test_name]: Expected permission=allow, got: $permission"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  echo "PASS [$test_name]: Allowed explicitly"
  PASS_COUNT=$((PASS_COUNT + 1))
}

echo "=== Testing block-bare-read deny cases ==="

cat_payload='{"tool_input": {"command": "cat /etc/passwd"}}'
assert_denied "$cat_payload" "Use the Read tool" "$BLOCK_BARE_READ" "bare cat"

head_payload='{"tool_input": {"command": "head -10 /etc/passwd"}}'
assert_denied "$head_payload" "Use the Read tool" "$BLOCK_BARE_READ" "bare head"

tail_payload='{"tool_input": {"command": "tail -20 /var/log/syslog"}}'
assert_denied "$tail_payload" "Use the Read tool" "$BLOCK_BARE_READ" "bare tail"

echo ""
echo "=== Testing block-bare-read allow/pass-through cases ==="

grep_pipeline='{"tool_input": {"command": "cat /etc/passwd | grep root"}}'
assert_passthrough "$grep_pipeline" "$BLOCK_BARE_READ" "cat with pipe (pass-through)"

npm_payload='{"tool_input": {"command": "npm test"}}'
assert_passthrough "$npm_payload" "$BLOCK_BARE_READ" "npm test (unrelated command, pass-through)"

tail_f_payload='{"tool_input": {"command": "tail -f /var/log/syslog"}}'
assert_passthrough "$tail_f_payload" "$BLOCK_BARE_READ" "tail -f (monitoring, pass-through)"

echo ""
echo "=== Testing translate-hook explicit allow handling ==="

# Create a test hook that returns explicit allow
cat > /tmp/test-allow-hook.sh << 'HOOK'
#!/bin/bash
jq -n '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "Test allow"}}'
HOOK
chmod +x /tmp/test-allow-hook.sh

allow_payload='{"tool_input": {"command": "test"}}'
assert_allowed "$allow_payload" "/tmp/test-allow-hook.sh" "explicit allow hook"

rm /tmp/test-allow-hook.sh

echo ""
echo "=== Testing stderr forwarding and exit-code propagation ==="

# Hook that writes to stderr, emits a deny, and exits 0
cat > /tmp/test-stderr-hook.sh << 'HOOK'
#!/bin/bash
echo "diagnostic from hook" >&2
jq -n '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "stderr test"}}'
HOOK
chmod +x /tmp/test-stderr-hook.sh

stderr_payload='{"tool_input": {"command": "test"}}'
stdout_out=$(bash "$TRANSLATE_HOOK" /tmp/test-stderr-hook.sh <<< "$stderr_payload" 2>/tmp/test-stderr-capture)
stderr_out=$(</tmp/test-stderr-capture)
if [[ "$stderr_out" == *"diagnostic from hook"* ]] \
   && [[ "$stdout_out" != *"diagnostic from hook"* ]] \
   && printf '%s' "$stdout_out" | jq -e '.permission == "deny"' >/dev/null 2>&1; then
  echo "PASS [stderr forwarded, stdout JSON clean]"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL [stderr forwarding]: stderr='$stderr_out' stdout='$stdout_out'"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
rm -f /tmp/test-stderr-hook.sh /tmp/test-stderr-capture

# Hook that exits non-zero: exit code must propagate
cat > /tmp/test-exit-hook.sh << 'HOOK'
#!/bin/bash
echo "failing hook" >&2
exit 3
HOOK
chmod +x /tmp/test-exit-hook.sh

bash "$TRANSLATE_HOOK" /tmp/test-exit-hook.sh <<< "$stderr_payload" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then
  echo "PASS [non-zero exit code propagates ($rc)]"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL [exit-code propagation]: expected 3, got $rc"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
rm -f /tmp/test-exit-hook.sh

echo ""
echo "=== Test Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "All tests passed!"
  exit 0
else
  echo "Some tests failed!"
  exit 1
fi
