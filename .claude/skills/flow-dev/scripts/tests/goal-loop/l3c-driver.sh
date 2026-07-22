#!/bin/bash
# tests/goal-loop/l3c-driver.sh
#
# L3c e2e driver for the spec-advisor /goal wrapper, per
# docs/specs/active/2026-05-27-spec-advisor-goal-wrapper.md §Testing
# (L3c row), §L3 feasibility, §/goal contract, §Required test cases,
# and §Acceptance criteria A2-auto.
#
# WHAT THIS DRIVER TESTS
#   "Given correct status-line emission, does the main agent's per-turn
#    behaviour terminate the loop at the spec-mandated turn?"
#
#   The L2 test (status-line-emit.sh) byte-exact verifies the EMITTER
#   (that simulate_turn produces the right status string). This L3c
#   driver verifies the EVALUATOR (that /goal's success / abort regexes
#   would fire at the expected turn given a sequence of status lines).
#   The two tiers are complementary; neither subsumes the other.
#
# WHAT THIS DRIVER DOES NOT TEST
#   - Claude Code / `claude --print` / interactive `/goal` invocation.
#     L3a (claude --print + /goal) is structurally unsupported per spec
#     §L3 feasibility (slash commands are interactive-mode-only;
#     upstream issue #837 tracks). L3b (expect/pty) was design-time
#     rejected. Haiku itself is exercised only out-of-repo via the
#     manual runbook in flow/references/loop-protocol.md.
#   - The status-line grammar itself — that is L2's job.
#
# CONTRACT MIRRORED HERE (verbatim from spec §/goal contract)
#   Success condition: latest line starting with `loop status:` contains
#                      `next_action=done`.
#   Abort condition:   latest line starting with `loop status:` contains
#                      `next_action=max_iter` OR `cycle=detected`.
#
#   In regex form (POSIX ERE, as bash =~ accepts):
#     success_re = '^loop status:.*next_action=done'
#     abort_re   = '^loop status:.*(next_action=max_iter|cycle=detected)'
#
# A4 INVARIANT
#   Driver does not import, source, or modify spec-advisory.sh /
#   spec-advisory-summary.sh / adversarial-review's Spec-gating mode
#   reviewer brief. The
#   status-line strings inlined below are the same strings L2 byte-exact
#   asserts against in status-line-emit.sh — they are not a new contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Spec §/goal contract — verbatim regexes Haiku token-matches against.
# Success is checked FIRST per spec §Haiku evaluation timing: a turn
# that emits next_action=done fires success before the next-turn entry
# condition is evaluated. Abort is checked AFTER, so a hypothetical
# pathological status line that contained both `done` and `max_iter`
# would correctly trip success first (this case is also structurally
# impossible given the enum semantics, but the ordering keeps the
# driver faithful to spec semantics).
SUCCESS_RE='^loop status:.*next_action=done'
ABORT_RE='^loop status:.*(next_action=max_iter|cycle=detected)'

PASSED=0
FAILED=0

# --- helpers -----------------------------------------------------------------

# simulate_goal — walk a sequence of status lines and find the turn at
# which /goal would terminate (success OR abort). Lines are consumed
# left-to-right; the first line matching success_re or abort_re ends
# the loop and yields the terminating turn index (1-based).
#
# Returns (via stdout) the integer turn index, or "NONE" if the sequence
# was exhausted without termination.
#
# $@ — the status lines, one per argv slot.
simulate_goal () {
  local turn=0
  local line
  for line in "$@"; do
    turn=$((turn + 1))
    if [[ "$line" =~ $SUCCESS_RE ]]; then
      printf '%s' "$turn"
      return 0
    fi
    if [[ "$line" =~ $ABORT_RE ]]; then
      printf '%s' "$turn"
      return 0
    fi
  done
  printf 'NONE'
}

# assert_terminate_turn — drive simulate_goal against a status-line
# sequence and assert termination occurred at the expected turn index.
#
# $1 case_label
# $2 expected_turn (integer)
# $3..N status lines
assert_terminate_turn () {
  local label="$1" expected="$2"
  shift 2
  local actual
  actual="$(simulate_goal "$@")"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $label — terminated at turn $actual (expected $expected)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $label — terminated at turn $actual (expected $expected)"
    echo "        status lines fed to simulate_goal:"
    local i=0 l
    for l in "$@"; do
      i=$((i + 1))
      echo "          turn=$i: $l"
    done
    FAILED=$((FAILED + 1))
  fi
}

# --- case status-line fixtures ----------------------------------------------
#
# Each case's status-line sequence is the byte-exact string L2's
# status-line-emit.sh asserts against (per L2 case run_case_*). Listed
# here as inlined heredoc-equivalent literals so the L3c driver does
# NOT need to source or re-execute L2; the contract between the two
# tiers is "L2 proves the emitter, L3c assumes that proof and tests
# the evaluator". Drift would be caught by L2 first.

run_case_all_clean () {
  echo "case all_clean (expect /goal success at turn 1):"
  local s1="loop status: iteration=1/5, next_action=done, findings=H:0 M:0 L:0, cycle=none"
  assert_terminate_turn "all_clean" 1 "$s1"
}

run_case_edit_then_clean () {
  echo "case edit_then_clean (expect /goal success at turn 2):"
  local s1="loop status: iteration=1/5, next_action=edit_spec, findings=H:2 M:1 L:0, cycle=none"
  local s2="loop status: iteration=2/5, next_action=done, findings=H:0 M:0 L:0, cycle=none"
  assert_terminate_turn "edit_then_clean" 2 "$s1" "$s2"
}

run_case_max_iter () {
  echo "case max_iter (expect /goal abort at turn 5):"
  local s1="loop status: iteration=1/5, next_action=edit_spec, findings=H:1 M:1 L:1, cycle=none"
  local s2="loop status: iteration=2/5, next_action=edit_spec, findings=H:1 M:1 L:1, cycle=none"
  local s3="loop status: iteration=3/5, next_action=edit_spec, findings=H:1 M:1 L:1, cycle=none"
  local s4="loop status: iteration=4/5, next_action=edit_spec, findings=H:1 M:1 L:1, cycle=none"
  local s5="loop status: iteration=5/5, next_action=max_iter, findings=H:1 M:1 L:1, cycle=none"
  assert_terminate_turn "max_iter" 5 "$s1" "$s2" "$s3" "$s4" "$s5"
}

run_case_cycle () {
  echo "case cycle (expect /goal abort at turn 2):"
  # Per spec §Required test cases: cycle is 2 turns; iter 2's spec_hash
  # matches iter 1's, so the main agent overrides next_action to
  # max_iter and sets cycle=detected. /goal abort fires at turn 2 on
  # the cycle=detected token (also matched by next_action=max_iter —
  # either disjunct is sufficient per spec §/goal contract).
  local s1="loop status: iteration=1/5, next_action=edit_spec, findings=H:1 M:1 L:1, cycle=none"
  local s2="loop status: iteration=2/5, next_action=max_iter, findings=H:1 M:1 L:1, cycle=detected"
  assert_terminate_turn "cycle" 2 "$s1" "$s2"
}

# --- driver ------------------------------------------------------------------

echo "goal-loop L3c driver:"
run_case_all_clean
run_case_edit_then_clean
run_case_max_iter
run_case_cycle

echo
echo "Results: $PASSED passed, $FAILED failed."
if [[ $FAILED -eq 0 ]]; then
  echo "l3c-driver: PASS"
  exit 0
else
  echo "l3c-driver: FAIL"
  exit 1
fi
