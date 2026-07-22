#!/usr/bin/env bash
# main-agent-loop termination test (rewrite of status-line-emit.sh).
# Tests the main-agent per-turn loop termination decision WITHOUT the
# Haiku status-line contract: given an envelope's signals, does the loop
# stop with the right reason? Cases mirror the spec test plan:
# all_clean / edit_then_clean / max_iter / cycle.
set -uo pipefail
cd "$(dirname "$0")"
PASS=0; FAIL=0

# assert_terminates <name> <expected-reason> <actual-reason>
# reason in: done | clean | cycle | max_iter | continue
assert_terminates () {
  if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1));
  else echo "FAIL $1: termination='$3' want '$2'"; FAIL=$((FAIL+1)); fi
}

# termination_reason <next_action> <H> <M> <cycle> <N> <MAX>
# Pure function mirroring the SKILL.md step-3 termination decision.
termination_reason () {
  local na="$1" h="$2" m="$3" cyc="$4" n="$5" max="$6"
  [ "$na" = "done" ] && { echo done; return; }
  [ "$h" -eq 0 ] && [ "$m" -eq 0 ] && { echo clean; return; }
  [ "$cyc" = "detected" ] && { echo cycle; return; }
  [ "$n" -ge "$max" ] && { echo max_iter; return; }
  echo continue
}

# Case all_clean: 1 turn, advisor says done -> terminate done
assert_terminates "all_clean" "done" "$(termination_reason done 0 0 none 1 5)"

# Case edit_then_clean: turn 2 reports H=0 M=0 -> terminate clean
assert_terminates "edit_then_clean" "clean" "$(termination_reason edit_spec 0 0 none 2 5)"

# Case max_iter: turn 5, still has findings, no cycle -> terminate max_iter
assert_terminates "max_iter" "max_iter" "$(termination_reason edit_spec 2 1 none 5 5)"

# Case cycle: spec_hash repeated + edit_spec -> cycle=detected -> terminate cycle
assert_terminates "cycle" "cycle" "$(termination_reason edit_spec 1 0 detected 2 5)"

# Case continue: findings remain, not capped, no cycle -> keep looping
assert_terminates "continue-when-work-remains" "continue" "$(termination_reason edit_spec 1 1 none 2 5)"

echo "---"; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
