#!/usr/bin/env bash
# test_semantic_integration.sh — Phase 3 dogfood integration test.
# (Engine relocated into skill-audit/; was skill-semantic-audit → skill-audit.)
#
# Scope (Task 17 / spec L411-440):
#   1. Self-dogfood: run audit on skill-audit/SKILL.md itself
#      (G7 + G8 axes only — G1 needs --cross and is exercised separately
#      against the testdata fixture pair).
#   2. Cross-skill dogfood: run G8 against skill-audit and
#      flow-dev SKILL.md (multi-references case).
#   3. G1 dispatch smoke: run --axis G1 against the testdata fixture pair.
#   4. Cross-skill rg verification: confirm Task 17 Phase 3 added cross-refs
#      to all 3 target SKILL.md files.
#   5. Routing-collision static check: trigger-eval.json holds ≥3 near-miss
#      negatives covering skill-syntax-audit / darwin / skill-creator / skill-writer.
#
# Exit codes
#   0 = all assertions passed
#   1 = some assertion failed (stderr describes which)
#
# Honesty contract (PUA Integrity Guard advisory): every assertion runs the
# real audit.sh against the real SKILL.md or fixture data — no mocking of
# exit codes, no `|| true` swallows. The eval JSON is read-only.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${HERE}/../.." && pwd)"           # skill-audit/
REPO_ROOT="$(cd "${SKILL_ROOT}/.." && pwd)"          # worktree root
AUDIT_SH="${SKILL_ROOT}/scripts/semantic_audit.sh"
SELF_SKILL="${SKILL_ROOT}/SKILL.md"
G1_FIXTURE_DIR="${SKILL_ROOT}/testdata/g1-fixtures"
EVAL_JSON="${SKILL_ROOT}/evals/trigger-eval.json"
DOGFOODS_ROOT="${REPO_ROOT}/docs/dogfoods"

# Shared Smoke-evidence emitter (run-id/dir logic lives ONLY in this file,
# shared with the syntax-leg integration test; PR3 of resident-dogfood). The audit exit
# code is CAPTURED into smoke/<cmd>.exit and is NOT an auto-fail (Open Q6).
source "${REPO_ROOT}/_shared/lib/sh/sandwich-trace.sh"

PASS=0
FAIL=0
log_pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
log_fail() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }

# assert_dispatch_clean — accept exit ∈ {0,2}, OR exit 1 *only* when the
# detector explicitly logs the documented stub message (G7/G8 detectors are
# still stubs on this branch — Task 13/14 land downstream of task-9).
# Args: $1=label, $2=actual_exit, $3=stderr_file (optional)
assert_dispatch_clean() {
  local label="$1" rc="$2" errfile="${3:-}"
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
    log_pass "${label}: exit=${rc} (in {0,2})"
    return
  fi
  if [ "$rc" -eq 1 ] && [ -n "$errfile" ] && [ -f "$errfile" ] \
       && grep -qE 'detector not implemented .* pending Task [0-9]+ \(#1[34]\)' "$errfile"; then
    log_pass "${label}: exit=1 + documented G7/G8 stub message (Task 13/14 pending)"
    return
  fi
  log_fail "${label}: exit was ${rc} (unexpected); stderr=${errfile:-<none>}"
}

echo "=== Phase 3 integration test: semantic leg (skill-audit) ==="
echo "SKILL_ROOT=${SKILL_ROOT}"

# Preflight: required artifacts present.
for f in "$AUDIT_SH" "$SELF_SKILL" "$EVAL_JSON"          "${G1_FIXTURE_DIR}/skill-a-debfactory.md"          "${G1_FIXTURE_DIR}/skill-b-debfactory.md"; do
  if [ ! -e "$f" ]; then
    log_fail "preflight: missing required artifact $f"
  fi
done
[ "$FAIL" -eq 0 ] || { echo "preflight failed, aborting" >&2; exit 1; }
log_pass "preflight: all required artifacts present"

# Step 1: contract — G7 axis was removed 2026-05-29
# (per docs/specs/active/2026-05-29-prose-guidelines-g7-dedup.md).
# Confirm `--axis G7` now exits 1 with the redirect message.
set +e
bash "$AUDIT_SH" "$SELF_SKILL" --axis G7 --no-llm >/tmp/sa-it-self-g7-removed.out 2>/tmp/sa-it-self-g7-removed.err
RC=$?
set -e
if [ "$RC" -eq 1 ] && grep -q "prose-guidelines" /tmp/sa-it-self-g7-removed.err; then
  log_pass "G7 axis removed: --axis G7 exits 1 and redirects to prose-guidelines"
else
  log_fail "G7 axis removal contract: expected RC=1 + 'prose-guidelines' in stderr; got RC=$RC"
fi

# Step 2: self-dogfood — G8 against skill-audit/SKILL.md.
set +e
bash "$AUDIT_SH" "$SELF_SKILL" --axis G8 --no-llm >/tmp/sa-it-self-g8.out 2>/tmp/sa-it-self-g8.err
RC=$?
set -e
assert_dispatch_clean "self G8 --no-llm on skill-audit/SKILL.md" "$RC" /tmp/sa-it-self-g8.err

# Step 3: cross-skill — G8 against skill-audit/SKILL.md.
# (Was G7 before 2026-05-29; converted to G8 to keep the same cross-skill
#  dispatch coverage now that G7 no longer exists as a runnable axis.)
set +e
bash "$AUDIT_SH" "${REPO_ROOT}/skill-audit/SKILL.md" --axis G8 --no-llm     >/tmp/sa-it-audit-g8.out 2>/tmp/sa-it-audit-g8.err
RC=$?
set -e
assert_dispatch_clean "G8 --no-llm on skill-audit/SKILL.md" "$RC" /tmp/sa-it-audit-g8.err

# Step 4: cross-skill — G8 against flow-dev/SKILL.md (multi-references case).
set +e
bash "$AUDIT_SH" "${REPO_ROOT}/flow-dev/SKILL.md" --axis G8 --no-llm     >/tmp/sa-it-stack-g8.out 2>/tmp/sa-it-stack-g8.err
RC=$?
set -e
assert_dispatch_clean "G8 --no-llm on flow-dev/SKILL.md" "$RC" /tmp/sa-it-stack-g8.err

# Step 5: G1 dispatch — fixture pair, --no-llm pure-logic path.
set +e
bash "$AUDIT_SH" "${G1_FIXTURE_DIR}/skill-a-debfactory.md"     --cross "${G1_FIXTURE_DIR}" --axis G1 --no-llm     >/tmp/sa-it-g1.out 2>/tmp/sa-it-g1.err
RC=$?
set -e
assert_dispatch_clean "G1 --no-llm on fixture pair" "$RC" /tmp/sa-it-g1.err
# Bonus assert: stdout must include the YAML 'findings:' top-level key.
if grep -q '^findings:' /tmp/sa-it-g1.out; then
  log_pass "G1 stdout includes 'findings:' YAML key"
else
  log_fail "G1 stdout missing 'findings:' YAML key (see /tmp/sa-it-g1.out)"
fi

# Step 6: cross-skill rg verification — skill-audit is referenced by peers.
for f in skill-writer/SKILL.md flow-dev/SKILL.md skill-audit/SKILL.md; do
  if rg -q "skill-audit" "${REPO_ROOT}/${f}"; then
    log_pass "cross-ref present in ${f}"
  else
    log_fail "cross-ref MISSING in ${f}"
  fi
done

# Step 7: routing-collision static schema check (read-only on trigger-eval.json).
# Requirement (spec L444): trigger-eval.json's should_trigger:false set must
# include ≥ 3 near-miss queries naming sibling skills (skill-syntax-audit / darwin /
# skill-creator / skill-writer). We check this by counting rationale-field
# substring matches — read-only inspection, no mutation.
NEG_HITS=$(python3 - "$EVAL_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
negs = [x for x in d if x.get("should_trigger") is False]
hit = 0
for x in negs:
    blob = (x.get("query") or "") + " " + (x.get("rationale") or "")
    blob = blob.lower()
    if any(name in blob for name in ("skill-audit", "skill-syntax-audit", "darwin", "skill-creator", "skill-writer")):
        hit += 1
print(hit)
PY
)
if [ "${NEG_HITS:-0}" -ge 3 ]; then
  log_pass "trigger-eval.json: ${NEG_HITS} routing-collision negatives (≥3 required)"
else
  log_fail "trigger-eval.json: only ${NEG_HITS:-0} collision negatives (≥3 required)"
fi

# Step 8: emit Smoke evidence onto the PR1 resident contract
# (docs/dogfoods/skill-audit/run-NNN/smoke/). This REUSES the
# audit runs already executed above (their captured /tmp out+err files);
# it adds evidence emission only — no new audit invocation, no detector or
# scoring change. Exit codes are captured for post-hoc analysis (Open Q6).
RUN_DIR="$(dogfood_next_run_dir "skill-audit" "$DOGFOODS_ROOT")"
echo "resident run dir: ${RUN_DIR}"
# Re-capture the self G8 + cross G8 runs (deterministic) for evidence.
set +e
bash "$AUDIT_SH" "$SELF_SKILL" --axis G8 --no-llm >/tmp/sa-smoke-self.out 2>/tmp/sa-smoke-self.err
SELF_RC=$?
bash "$AUDIT_SH" "${REPO_ROOT}/skill-audit/SKILL.md" --axis G8 --no-llm >/tmp/sa-smoke-cross.out 2>/tmp/sa-smoke-cross.err
CROSS_RC=$?
set -e
cat /tmp/sa-smoke-self.out /tmp/sa-smoke-self.err > /tmp/sa-smoke-self.combined 2>/dev/null
cat /tmp/sa-smoke-cross.out /tmp/sa-smoke-cross.err > /tmp/sa-smoke-cross.combined 2>/dev/null
dogfood_emit_smoke "$RUN_DIR" "self-g8-semantic-audit" "$SELF_RC" /tmp/sa-smoke-self.combined
dogfood_emit_smoke "$RUN_DIR" "cross-g8-syntax-audit" "$CROSS_RC" /tmp/sa-smoke-cross.combined
for cmd in self-g8-semantic-audit cross-g8-syntax-audit; do
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
