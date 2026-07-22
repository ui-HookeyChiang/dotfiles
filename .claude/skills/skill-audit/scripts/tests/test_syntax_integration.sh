#!/usr/bin/env bash
# test_syntax_integration.sh — syntax-leg self-dogfood + Smoke evidence emit.
# (Engine relocated into skill-audit/; was skill-syntax-audit → skill-audit.)
#
# Scope (PR3 of resident-dogfood):
#   1. Self-dogfood: run syntax_audit.sh against skill-audit/SKILL.md.
#      SKILL.md "Exit codes" documents this as the success case: a well-
#      maintained small skill scores composite < 30 -> exit 2 ("clean").
#      Accept exit in {0,2}; exit 1 is a real tool error and fails the test.
#   2. Cross-skill dogfood: run syntax_audit.sh against the neighbour
#      skill-audit/SKILL.md (cross-skill dispatch coverage).
#   3. Emit Smoke evidence onto the PR1 resident contract
#      (docs/dogfoods/skill-audit/run-NNN/smoke/) via the SHARED helper
#      _shared/lib/sh/sandwich-trace.sh. The audit exit code is CAPTURED into
#      smoke/<cmd>.exit; a non-zero audit exit is NOT an auto-fail (spec
#      Open Q6) — only a genuine tool error (exit 1) fails the integration test.
#
# Exit codes
#   0 = all assertions passed
#   1 = some assertion failed (stderr describes which)
#
# Honesty contract: every assertion runs the real audit.sh against the real
# SKILL.md — no mocking, no `|| true` swallows. Evidence emission wraps the
# real runs; it does not change what the audit checks or how it scores.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${HERE}/../.." && pwd)"            # skill-audit/
REPO_ROOT="$(cd "${SKILL_ROOT}/.." && pwd)"           # worktree root
AUDIT_SH="${SKILL_ROOT}/scripts/syntax_audit.sh"
SELF_SKILL="${SKILL_ROOT}/SKILL.md"
NEIGHBOUR_SKILL="${REPO_ROOT}/skill-audit/SKILL.md"
DOGFOODS_ROOT="${REPO_ROOT}/docs/dogfoods"

# Shared Smoke-evidence emitter (run-id/dir logic lives ONLY here).
source "${REPO_ROOT}/_shared/lib/sh/sandwich-trace.sh"

PASS=0
FAIL=0
log_pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
log_fail() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }

# assert_audit_clean — accept exit in {0,2} (advisory composite vs threshold);
# exit 1 is a real tool error -> fail. Returns the exit code for capture.
assert_audit_clean() {
  local label="$1" rc="$2"
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
    log_pass "${label}: exit=${rc} (in {0,2})"
  else
    log_fail "${label}: exit was ${rc} (expected 0 or 2; 1 = tool error)"
  fi
}

echo "=== integration test: syntax leg (skill-audit) ==="
echo "SKILL_ROOT=${SKILL_ROOT}"

# Preflight.
for f in "$AUDIT_SH" "$SELF_SKILL" "$NEIGHBOUR_SKILL"; do
  [ -e "$f" ] || log_fail "preflight: missing required artifact $f"
done
[ "$FAIL" -eq 0 ] || { echo "preflight failed, aborting" >&2; exit 1; }
log_pass "preflight: all required artifacts present"

# Allocate ONE resident run dir for this integration pass (Smoke depth).
RUN_DIR="$(dogfood_next_run_dir "skill-audit" "$DOGFOODS_ROOT")"
echo "resident run dir: ${RUN_DIR}"

# Step 1: self-dogfood — syntax_audit.sh against own SKILL.md.
set +e
bash "$AUDIT_SH" "$SELF_SKILL" --no-llm >/tmp/syn-it-self.out 2>/tmp/syn-it-self.err
RC=$?
set -e
assert_audit_clean "self --no-llm on skill-audit/SKILL.md" "$RC"
cat /tmp/syn-it-self.out /tmp/syn-it-self.err > /tmp/syn-it-self.combined 2>/dev/null
dogfood_emit_smoke "$RUN_DIR" "self-syntax-audit" "$RC" /tmp/syn-it-self.combined

# Step 2: cross-skill dogfood — audit.sh against neighbour SKILL.md.
set +e
bash "$AUDIT_SH" "$NEIGHBOUR_SKILL" --no-llm >/tmp/syn-it-cross.out 2>/tmp/syn-it-cross.err
RC=$?
set -e
assert_audit_clean "cross --no-llm on skill-audit/SKILL.md" "$RC"
cat /tmp/syn-it-cross.out /tmp/syn-it-cross.err > /tmp/syn-it-cross.combined 2>/dev/null
dogfood_emit_smoke "$RUN_DIR" "cross-semantic-audit" "$RC" /tmp/syn-it-cross.combined

# Step 3: assert Smoke evidence landed on the contract.
for cmd in self-syntax-audit cross-semantic-audit; do
  if [ -f "${RUN_DIR}/smoke/${cmd}.log" ] && [ -f "${RUN_DIR}/smoke/${cmd}.exit" ]; then
    log_pass "Smoke evidence emitted: smoke/${cmd}.{log,exit}"
  else
    log_fail "Smoke evidence MISSING for ${cmd} under ${RUN_DIR}/smoke/"
  fi
done

# Uniform dogfood completion trace (dogfood-residency-enforcement): give all
# three consumers a single `grep gate=e2e-pass:` surface. audit is already
# CI-forced (this test); the trace adds NO new gate and NO new failure mode —
# dogfood_emit_trace is best-effort and always returns 0.
TRACE_RUN="$(basename "$RUN_DIR")"; TRACE_RUN="${TRACE_RUN#run-}"
SPEC_FILE="${REPO_ROOT}/docs/specs/active/2026-06-01-dogfood-residency-enforcement.md"
if [ -f "$SPEC_FILE" ]; then
  TRACE_HASH="$(git -C "$REPO_ROOT" hash-object "$SPEC_FILE" 2>/dev/null | cut -c1-12)"
else
  TRACE_HASH="unknown000000"
fi
TRACE_LOG="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null)/flow-dev-sandwich.log"
dogfood_emit_trace "audit" "${TRACE_HASH:-unknown000000}" "smoke" "$TRACE_RUN" "ok" "$TRACE_LOG"

echo ""
echo "=== summary: PASS=${PASS}  FAIL=${FAIL} ==="
if [ "$FAIL" -gt 0 ]; then
  echo "test_integration.sh FAILED" >&2
  exit 1
fi
exit 0
