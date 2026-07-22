#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
PASS=0; FAIL=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1));
  else echo "FAIL $1: got '$3' want '$2'"; FAIL=$((FAIL+1)); fi
}
SKILL="../../../SKILL.md"

# Case 1: DRAFT makes the loop the Phase 1 default + names full as fallback
if [ -f "$SKILL" ] \
  && grep -q 'Phase 1 spec-advisory enters the loop by default' "$SKILL" \
  && grep -q 'fallback' "$SKILL" \
  && grep -q 'next_action == done' "$SKILL"; then
  check "draft-loop-is-default" "ok" "ok"
else
  check "draft-loop-is-default" "ok" "missing"
fi

# Case 2: DRAFT documents the fallback-also-fails terminal STOP
if [ -f "$SKILL" ] && grep -q 'no further fallback' "$SKILL"; then
  check "draft-fallback-terminal" "ok" "ok"
else
  check "draft-fallback-terminal" "ok" "missing"
fi

# Case 3: auto-removed.sh exists (skill-writer runs it post-removal; here guard presence)
if [ -f auto-removed.sh ]; then
  check "auto-removed-test-present" "ok" "ok"
else
  check "auto-removed-test-present" "ok" "missing"
fi

echo "---"; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
