#!/bin/bash
# tests/spec-lint-warn/test.sh
# Verify the 3-tier exit code contract of spec-lint.sh:
#   pass.md  -> exit 0 (PASS)
#   warn.md  -> exit 1 (WARN)
#   fail.md  -> exit 2 (FAIL)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKING_DEV="$(cd "$HERE/../../.." && pwd)"
LINT="$STACKING_DEV/scripts/spec-lint.sh"

PASSED=0
FAILED=0

assert_exit () {
  local label="$1"
  local expected="$2"
  local fixture="$3"
  local actual
  set +e
  bash "$LINT" "$fixture" >/dev/null 2>&1
  actual=$?
  set -e
  if [[ $actual -eq $expected ]]; then
    echo "  PASS: $label (exit $actual)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $label — expected exit $expected, got $actual"
    bash "$LINT" "$fixture" 2>&1 || true
    FAILED=$((FAILED + 1))
  fi
}

echo "spec-lint-warn suite:"
assert_exit "pass.md -> exit 0 (PASS)" 0 "$HERE/pass.md"
assert_exit "warn.md -> exit 1 (WARN)" 1 "$HERE/warn.md"
assert_exit "fail.md -> exit 2 (FAIL)" 2 "$HERE/fail.md"

echo
echo "Results: $PASSED passed, $FAILED failed."
if [[ $FAILED -eq 0 ]]; then
  echo "spec-lint-warn: PASS"
  exit 0
else
  echo "spec-lint-warn: FAIL"
  exit 1
fi
