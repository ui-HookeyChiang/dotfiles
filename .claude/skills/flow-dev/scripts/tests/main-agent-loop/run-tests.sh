#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
PASS=0; FAIL=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1));
  else echo "FAIL $1: got '$3' want '$2'"; FAIL=$((FAIL+1)); fi
}

# Case 1: DRAFT loop is main-agent-driven (no dependency on the /goal+Haiku mechanism)
SKILL="../../../SKILL.md"
if [ -f "$SKILL" ] \
  && grep -q 'main agent drives the loop directly' "$SKILL" \
  && ! grep -qi 'driven via.*/goal\|/goal.*slash command\|wraps the loop\|delegates termination\|Haiku.*\(token-match\|evaluat\|scores\|judges\|decides\) the\|evaluated by.*Haiku' "$SKILL" \
  && ! grep -q 'Emit .loop status:. line' "$SKILL"; then
  check "draft-main-agent-driven-no-mechanism" "ok" "ok"
else
  check "draft-main-agent-driven-no-mechanism" "ok" "missing"
fi

# Case 2: DRAFT keeps objective termination signals
if [ -f "$SKILL" ] \
  && grep -q 'next_action == done' "$SKILL" \
  && grep -q 'cycle' "$SKILL" \
  && grep -q 'max_iter' "$SKILL"; then
  check "draft-keeps-termination-signals" "ok" "ok"
else
  check "draft-keeps-termination-signals" "ok" "missing"
fi

# Case 3: rewritten-test DRAFT keeps 4 cases + termination logic, drops Haiku status-format
APPLIED="../goal-loop/status-line-emit.sh"
if [ -f "$APPLIED" ] \
  && grep -q 'all_clean' "$APPLIED" && grep -q 'edit_then_clean' "$APPLIED" \
  && grep -q 'max_iter' "$APPLIED" && grep -q 'cycle' "$APPLIED" \
  && grep -q 'assert_terminates' "$APPLIED" \
  && ! grep -q 'assert_status_line' "$APPLIED" \
  && ! grep -q 'assert_last_line_is_status' "$APPLIED"; then
  check "test-draft-keeps-cases-drops-statusfmt" "ok" "ok"
else
  check "test-draft-keeps-cases-drops-statusfmt" "ok" "missing"
fi

echo "---"; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
