#!/usr/bin/env bash
# skill-audit/tests/integration-2agent.sh
# Integration regression: full skill-audit dispatches exactly 2 LLM agents
# regardless of reference count; deterministic side runs 0 agents; trace gate
# enforces 2 legs.
#
# Three assertions (per HANDOFF.md Task 8):
#   A1. Composer banner names probabilistic + prose, NEVER syntax-llm.
#       Tested against flow-dev (12 references) to prove ref-count-independence.
#   A2. Trace gate: 1 leg written -> assert_audit_complete fails;
#                   2 legs written -> assert_audit_complete passes.
#   A3. Deterministic run.sh exits 0 or 2 (never 1) against flow-dev.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TRACE_SH="$ROOT/_shared/lib/sh/sandwich-trace.sh"
SKILL="$ROOT/flow-dev"
PASS=0; FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }

# ── A1: Composer banner names probabilistic + prose, NEVER syntax-llm ─────────
ERR="$(mktemp)"
out="$(SKILL_AUDIT_SKILLS_ROOT="$ROOT" python3 "$HERE/scripts/skill-audit.py" "$SKILL" 2>"$ERR")"
composer_rc=$?
err="$(cat "$ERR")"; rm -f "$ERR"

# A1 precondition: the banner prints even when the composer ERRORED (any_error
# -> banner still emitted, exit 1). Without this guard A1 cannot tell "ran
# correctly" from "errored but happened to print the banner". rc must be 0
# (problem found) or 2 (clean) — NOT 1 (engine error).
#
# The sub-checks (A1a/A1b/A1c) are GATED on rc∈{0,2}. On a composer crash the
# banner output is empty/untrustworthy, and A1c's absence-grep ("syntax-llm
# absent") would FALSE-PASS on empty input — so when A1-pre fails we mark the
# sub-checks failed, never silently passed.
if { [ "$composer_rc" = 0 ] || [ "$composer_rc" = 2 ]; }; then
  pass "A1-pre: composer exit $composer_rc (0 or 2, not 1=error)"

  printf '%s\n' "$err" | /bin/grep -q "probabilistic" \
    && pass "A1a: 'probabilistic' present in banner" \
    || fail "A1a: 'probabilistic' missing from stderr banner"

  printf '%s\n' "$err" | /bin/grep -q "prose" \
    && pass "A1b: 'prose' present in banner" \
    || fail "A1b: 'prose' missing from stderr banner"

  printf '%s\n%s\n' "$out" "$err" | /bin/grep -q "syntax-llm" \
    && fail "A1c: stale 'syntax-llm' leg still referenced in output" \
    || pass "A1c: 'syntax-llm' absent from both streams"
else
  fail "A1-pre: composer errored (rc=$composer_rc) — banner content untrustworthy"
  fail "A1a/A1b/A1c: skipped — composer crash makes banner grep unreliable (A1c absence-grep would false-pass on empty output)"
fi

# ── A2: Trace gate — 1 leg fails, 2 legs pass ─────────────────────────────────
# Division of labour: A1 proves the composer names EXACTLY the 2 LLM legs (the
# dispatch COUNT); A2 proves the trace GATE enforces both legs before complete.
# A2 deliberately does NOT re-invoke the composer — that is A1's job.
# A2a and A2b use SEPARATE log files so each case is independent. (A shared log
# would let A2b pass on A2a's leftover 'probabilistic' line — masking an A2a
# regression.) A2a: only probabilistic. A2b: both legs from scratch.
LOG_A="$(mktemp)"
bash -c "
  source '$TRACE_SH'
  write_audit_leg_trace probabilistic flow-dev '$LOG_A'
  assert_audit_complete flow-dev '$LOG_A'
" >/dev/null 2>&1
rc=$?
[ "$rc" != 0 ] \
  && pass "A2a: 1-of-2 legs -> assert_audit_complete correctly returns non-zero (rc=$rc)" \
  || fail "A2a: 1-of-2 legs -> assert_audit_complete incorrectly returned 0"
rm -f "$LOG_A"

LOG_B="$(mktemp)"
bash -c "
  source '$TRACE_SH'
  write_audit_leg_trace probabilistic flow-dev '$LOG_B'
  write_audit_leg_trace prose         flow-dev '$LOG_B'
  assert_audit_complete flow-dev '$LOG_B'
" >/dev/null 2>&1
rc=$?
[ "$rc" = 0 ] \
  && pass "A2b: 2-of-2 legs -> assert_audit_complete returns 0" \
  || fail "A2b: 2-of-2 legs -> assert_audit_complete returned non-zero (rc=$rc)"
rm -f "$LOG_B"

# ── A3: Deterministic run.sh exits 0 or 2 (no LLM, no agent) ─────────────────
# Strict: success is EXACTLY 0 (problem) or 2 (clean). Any other code — 1
# (engine error), 127 (script not found), etc. — fails. (A bare `rc != 1`
# check would pass on 127.)
bash "$ROOT/skill-audit/scripts/run.sh" "$SKILL" >/dev/null 2>&1
rc=$?
{ [ "$rc" = 0 ] || [ "$rc" = 2 ]; } \
  && pass "A3: run.sh exits $rc (0=problem or 2=clean)" \
  || fail "A3: run.sh exit $rc (expected 0 or 2; 1=error, 127=not-found)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] && exit 0 || exit 1
