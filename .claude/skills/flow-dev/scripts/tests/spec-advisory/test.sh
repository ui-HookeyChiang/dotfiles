#!/bin/bash
# tests/spec-advisory/test.sh
# Verify spec-advisory.sh full-mode contract:
#   AC1: 300-word spec  -> exit 0, stdout `mode=skip`
#   AC2: 1200-word spec -> exit 0, stdout `mode=light`
#   AC3: 3000-word spec -> exit 0, stdout `mode=deep`
#   AC4: nonexistent    -> exit 2, stderr `spec-advisory: file not found`
#   AC6 (partial): SD_SKIP_ADVISORY=1 forces mode=skip; missing --mode -> exit 2;
#                  bad --mode value -> exit 2

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKING_DEV="$(cd "$HERE/../../.." && pwd)"
ADVISORY="$STACKING_DEV/scripts/spec-advisory.sh"

PASSED=0
FAILED=0

# --- helpers -----------------------------------------------------------------
assert_stdout_and_exit () {
  # $1 label, $2 expected_exit, $3 expected_stdout_regex, $4... args to ADVISORY
  local label="$1" expected_exit="$2" expected_regex="$3"
  shift 3
  local out actual
  set +e
  out="$(bash "$ADVISORY" "$@" 2>/dev/null)"
  actual=$?
  set -e
  if [[ $actual -ne $expected_exit ]]; then
    echo "  FAIL: $label — expected exit $expected_exit, got $actual"
    echo "        stdout: $out"
    FAILED=$((FAILED + 1))
    return
  fi
  if ! echo "$out" | /bin/grep -qE "$expected_regex"; then
    echo "  FAIL: $label — stdout did not match /$expected_regex/"
    echo "        stdout: $out"
    FAILED=$((FAILED + 1))
    return
  fi
  echo "  PASS: $label (exit $actual, stdout matches /$expected_regex/)"
  PASSED=$((PASSED + 1))
}

assert_stderr_and_exit () {
  # $1 label, $2 expected_exit, $3 expected_stderr_regex, $4... args
  local label="$1" expected_exit="$2" expected_regex="$3"
  shift 3
  local err actual
  set +e
  err="$(bash "$ADVISORY" "$@" 2>&1 1>/dev/null)"
  actual=$?
  set -e
  if [[ $actual -ne $expected_exit ]]; then
    echo "  FAIL: $label — expected exit $expected_exit, got $actual"
    echo "        stderr: $err"
    FAILED=$((FAILED + 1))
    return
  fi
  if ! echo "$err" | /bin/grep -qE "$expected_regex"; then
    echo "  FAIL: $label — stderr did not match /$expected_regex/"
    echo "        stderr: $err"
    FAILED=$((FAILED + 1))
    return
  fi
  echo "  PASS: $label (exit $actual, stderr matches /$expected_regex/)"
  PASSED=$((PASSED + 1))
}

echo "spec-advisory full-mode suite:"

# AC1 — under always-three rule, short specs route to deep (per
# 2026-05-24-spec-advisory-always-three-agents.md). Fixture name retained.
assert_stdout_and_exit \
  "AC1: deep (300w, was skip pre always-three)" 0 '^mode=deep$' \
  --mode=full "$HERE/skip-300w.md"

# AC2 — under always-three rule, mid-size specs route to deep.
assert_stdout_and_exit \
  "AC2: deep (1200w, was light pre always-three)" 0 '^mode=deep$' \
  --mode=full "$HERE/light-1200w.md"

# AC3
assert_stdout_and_exit \
  "AC3: deep (3000w)" 0 '^mode=deep$' \
  --mode=full "$HERE/deep-3000w.md"

# AC4 — nonexistent file -> exit 2 + stderr token
assert_stderr_and_exit \
  "AC4: nonexistent -> exit 2 + file not found" 2 'spec-advisory: file not found' \
  --mode=full /nonexistent-spec-advisory-fixture-path.md

# AC6 (partial): bypass env var forces skip even on a deep-sized spec.
SD_SKIP_ADVISORY=1 bash "$ADVISORY" --mode=full "$HERE/deep-3000w.md" > /tmp/spec-advisory-bypass.$$ 2>&1
bypass_exit=$?
bypass_out="$(cat /tmp/spec-advisory-bypass.$$)"
rm -f /tmp/spec-advisory-bypass.$$
if [[ $bypass_exit -eq 0 && "$bypass_out" == "mode=skip" ]]; then
  echo "  PASS: AC6: SD_SKIP_ADVISORY=1 forces mode=skip (exit 0)"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: AC6: SD_SKIP_ADVISORY=1 — exit=$bypass_exit out=$bypass_out"
  FAILED=$((FAILED + 1))
fi

# AC6 (partial): missing --mode -> exit 2
assert_stderr_and_exit \
  "AC6: missing --mode -> exit 2" 2 'spec-advisory: --mode is required|spec-advisory: usage' \
  "$HERE/skip-300w.md"

# AC6 (partial): invalid --mode -> exit 2
assert_stderr_and_exit \
  "AC6: --mode=garbage -> exit 2" 2 "invalid --mode" \
  --mode=garbage "$HERE/skip-300w.md"

# AC5-removed — `--mode=auto` was removed (zero-caller orphan; see
# 2026-06-02-all-loop-default). It must now be REJECTED like any invalid mode.
assert_stderr_and_exit \
  "AC5-removed: --mode=auto -> exit 2 (mode removed)" 2 "invalid --mode" \
  --mode=auto "$HERE/skip-300w.md"

# =============================================================================
# === Loop mode (--mode=full-loop) — full-loop spec, 2026-05-25 ===============
# =============================================================================
# These ACs cover the new --mode=full-loop dispatcher introduced by
# 2026-05-25-spec-advisory-full-loop.md. They are appended AFTER the PR
# #522 ACs so existing AC numbering stays intact.

# Helpers for JSON-field assertions (loop envelope is JSON, not a plain line).
assert_json_field () {
  # $1 label, $2 expected, $3 jq filter, $4... args
  local label="$1" expected="$2" filter="$3"
  shift 3
  local out actual_exit actual_val
  set +e
  out="$(bash "$ADVISORY" "$@" 2>/dev/null)"
  actual_exit=$?
  set -e
  if [[ $actual_exit -ne 0 ]]; then
    echo "  FAIL: $label — script exited $actual_exit (expected 0)"
    echo "        stdout: $out"
    FAILED=$((FAILED + 1))
    return
  fi
  actual_val=$(echo "$out" | jq -r "$filter")
  if [[ "$actual_val" != "$expected" ]]; then
    echo "  FAIL: $label — expected $filter == '$expected', got '$actual_val'"
    echo "        stdout: $out"
    FAILED=$((FAILED + 1))
    return
  fi
  echo "  PASS: $label ($filter == '$expected')"
  PASSED=$((PASSED + 1))
}

echo
echo "spec-advisory full-loop suite:"

# Build a deterministic dirty-findings JSON (1 HIGH + 1 MED + 1 LOW).
LOOP_MOCK_DIRTY="$(mktemp -t loop-mock-dirty.XXXXXX.json)"
printf '%s\n' '[' \
  '{"severity":"HIGH","title":"missing S-T mapping","where":"§Success criteria","why":"S2 has no T-row","suggestion":"add T2 row"},' \
  '{"severity":"MED","title":"vague test step","where":"§Test plan T1","why":"verify X works has no exit code","suggestion":"specify exit 0"},' \
  '{"severity":"LOW","title":"trailing whitespace","where":"line 42","why":"style nitpick"}' \
  ']' > "$LOOP_MOCK_DIRTY"

# AC-LOOP-1: clean iteration=1 (no mock → empty findings) → next_action=done
assert_json_field \
  "AC-LOOP-1: loop iter=1 clean → next_action=done" \
  "done" ".next_action" \
  --mode=full-loop --iteration=1 "$HERE/loop-clean-first-pass.md"

assert_json_field \
  "AC-LOOP-1b: loop iter=1 clean → terminated=all_clean" \
  "all_clean" ".terminated" \
  --mode=full-loop --iteration=1 "$HERE/loop-clean-first-pass.md"

# AC-LOOP-2: dirty mock at iter=1 → next_action=edit_spec; findings preserved.
SD_ADVISORY_MOCK="$LOOP_MOCK_DIRTY" assert_json_field \
  "AC-LOOP-2: loop iter=1 dirty mock → next_action=edit_spec" \
  "edit_spec" ".next_action" \
  --mode=full-loop --iteration=1 "$HERE/loop-fix-then-clean.md"

SD_ADVISORY_MOCK="$LOOP_MOCK_DIRTY" assert_json_field \
  "AC-LOOP-2b: dirty mock findings_summary.H == 1" \
  "1" ".findings_summary.H" \
  --mode=full-loop --iteration=1 "$HERE/loop-fix-then-clean.md"

SD_ADVISORY_MOCK="$LOOP_MOCK_DIRTY" assert_json_field \
  "AC-LOOP-2c: dirty mock findings array length == 3" \
  "3" ".findings | length" \
  --mode=full-loop --iteration=1 "$HERE/loop-fix-then-clean.md"

# AC-LOOP-3: max iteration with dirty mock → next_action=max_iter
SD_ADVISORY_MOCK="$LOOP_MOCK_DIRTY" assert_json_field \
  "AC-LOOP-3: loop iter=5 dirty → next_action=max_iter" \
  "max_iter" ".next_action" \
  --mode=full-loop --iteration=5 "$HERE/loop-max-iter.md"

SD_ADVISORY_MOCK="$LOOP_MOCK_DIRTY" assert_json_field \
  "AC-LOOP-3b: terminated=max_iterations at iter=5" \
  "max_iterations" ".terminated" \
  --mode=full-loop --iteration=5 "$HERE/loop-max-iter.md"

# AC-LOOP-4: SD_ADVISORY_MAX_ITER=2 with iter=2 + dirty mock → max_iter
SD_ADVISORY_MAX_ITER=2 SD_ADVISORY_MOCK="$LOOP_MOCK_DIRTY" assert_json_field \
  "AC-LOOP-4: SD_ADVISORY_MAX_ITER=2 + iter=2 → terminated=max_iterations" \
  "max_iterations" ".terminated" \
  --mode=full-loop --iteration=2 "$HERE/loop-max-iter.md"

# AC-LOOP-5: SD_SKIP_ADVISORY=1 in loop mode → mode=skip envelope, no work.
SD_SKIP_ADVISORY=1 assert_json_field \
  "AC-LOOP-5: SD_SKIP_ADVISORY=1 + --mode=full-loop → mode=skip" \
  "skip" ".mode" \
  --mode=full-loop --iteration=1 "$HERE/loop-clean-first-pass.md"

SD_SKIP_ADVISORY=1 assert_json_field \
  "AC-LOOP-5b: SD_SKIP_ADVISORY=1 → reason=SD_SKIP_ADVISORY" \
  "SD_SKIP_ADVISORY" ".reason" \
  --mode=full-loop --iteration=1 "$HERE/loop-clean-first-pass.md"

# AC-LOOP-6: bad --iteration value → exit 2
assert_stderr_and_exit \
  "AC-LOOP-6: bad --iteration value → exit 2" 2 \
  "iteration must be a positive integer" \
  --mode=full-loop --iteration=garbage "$HERE/loop-clean-first-pass.md"

# AC-LOOP-7: spec_hash is a 12-char hex string (sha256 prefix)
assert_json_field \
  "AC-LOOP-7: spec_hash length is 12 chars" \
  "12" ".spec_hash | length" \
  --mode=full-loop --iteration=1 "$HERE/loop-clean-first-pass.md"

# AC-LOOP-8: iteration defaults to 1 when --iteration absent.
assert_json_field \
  "AC-LOOP-8: --iteration absent defaults to 1" \
  "1" ".iteration" \
  --mode=full-loop "$HERE/loop-clean-first-pass.md"

# AC-LOOP-REG: --mode=full byte-identical to PR #522 — already covered by
# the pre-existing AC1/AC2/AC3 above. Re-asserted here for documentation
# clarity (cheap to run; uses the same script invocation).
assert_stdout_and_exit \
  "AC-LOOP-REG: --mode=full regression (skip-300w still mode=deep)" 0 '^mode=deep$' \
  --mode=full "$HERE/skip-300w.md"

# Summary script ACs (D4) — exercise spec-advisory-summary.sh directly.
SUMMARY="$STACKING_DEV/scripts/spec-advisory-summary.sh"
LOOP_HISTORY="$(mktemp -t loop-history.XXXXXX.jsonl)"
SD_ADVISORY_MOCK="$LOOP_MOCK_DIRTY" bash "$ADVISORY" \
  --mode=full-loop --iteration=1 "$HERE/loop-fix-then-clean.md" \
  >> "$LOOP_HISTORY" 2>/dev/null
SD_ADVISORY_MOCK="$LOOP_MOCK_DIRTY" bash "$ADVISORY" \
  --mode=full-loop --iteration=2 "$HERE/loop-fix-then-clean.md" \
  >> "$LOOP_HISTORY" 2>/dev/null

set +e
SUMMARY_OUT="$(bash "$SUMMARY" "$LOOP_HISTORY" "$HERE/loop-fix-then-clean.md" 2>&1)"
SUMMARY_EXIT=$?
set -e
if [[ $SUMMARY_EXIT -eq 0 ]]; then
  H2_COUNT=$(echo "$SUMMARY_OUT" | /bin/grep -cE '^## (Spec|Iterations|Diff|LOW residue|Termination)$' || true)
  if [[ "$H2_COUNT" == "5" ]]; then
    echo "  PASS: AC-LOOP-SUMMARY: 5 required H2 sections present"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: AC-LOOP-SUMMARY: expected 5 H2 sections, got $H2_COUNT"
    echo "        output: $SUMMARY_OUT"
    FAILED=$((FAILED + 1))
  fi
else
  echo "  FAIL: AC-LOOP-SUMMARY: script exited $SUMMARY_EXIT"
  echo "        output: $SUMMARY_OUT"
  FAILED=$((FAILED + 1))
fi

# AC-LOOP-SUMMARY-USAGE: missing args → exit 2.
set +e
bash "$SUMMARY" 2>/dev/null
USAGE_EXIT=$?
set -e
if [[ $USAGE_EXIT -eq 2 ]]; then
  echo "  PASS: AC-LOOP-SUMMARY-USAGE: missing args → exit 2"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: AC-LOOP-SUMMARY-USAGE: expected exit 2, got $USAGE_EXIT"
  FAILED=$((FAILED + 1))
fi

rm -f "$LOOP_MOCK_DIRTY" "$LOOP_HISTORY"

# AC12 removed — the Agent C schema test (test-agent-c-schema.sh) validated the
# retired prompt-template file. The reviewer brief migrated into
# adversarial-review's Spec-gating mode section; that skill's own contract
# (frontmatter + Spec-gating mode rubric) is verified by its evals and by
# static-checks.sh AC8a/b/c + AC-r5-10/11.

# AC13: sandwich sidecar removed — envelope must NOT contain sandwich key
# (sidecar read/emit dropped; prose-guidelines fires at write-time instead)
echo "AC13: sandwich field absent from envelope (sidecar removed)"
AC13_TMP=$(mktemp -d)
cat > "$AC13_TMP/spec.md" <<'AC13EOF'
---
title: ac13-test
status: proposed
---
# Test
## Success criteria
- S1: bash test.sh exits 0
AC13EOF
echo '[{"severity":"HIGH","title":"x","where":"x","why":"x","suggestion":"x"}]' \
  > "$AC13_TMP/mock-findings.json"
AC13_ENV=$(SD_ADVISORY_MOCK="$AC13_TMP/mock-findings.json" \
  bash "$(dirname "$0")/../../spec-advisory.sh" --mode=full-loop --iteration=1 "$AC13_TMP/spec.md" 2>/dev/null)
if echo "$AC13_ENV" | jq -e 'has("sandwich")' >/dev/null 2>&1; then
  echo "  FAIL AC13: envelope still contains sandwich field"
  FAILED=$((FAILED + 1))
else
  echo "  PASS AC13: envelope has no sandwich field"
  PASSED=$((PASSED + 1))
fi
rm -rf "$AC13_TMP"


# AC-NO-SANDWICH: envelope must NOT contain sandwich key after sidecar removal
echo "AC-NO-SANDWICH: envelope must have no sandwich field"
_no_sandwich_out="$(bash "$ADVISORY" --mode=full-loop --iteration=1 "$HERE/loop-clean-first-pass.md" 2>/dev/null)"
if echo "$_no_sandwich_out" | jq -e 'has("sandwich")' >/dev/null 2>&1; then
  echo "  FAIL: AC-NO-SANDWICH: envelope still emits sandwich field"
  FAILED=$((FAILED + 1))
else
  echo "  PASS: AC-NO-SANDWICH: no sandwich field in envelope"
  PASSED=$((PASSED + 1))
fi

echo
echo "Results: $PASSED passed, $FAILED failed."
if [[ $FAILED -eq 0 ]]; then
  echo "spec-advisory: PASS"
  exit 0
else
  echo "spec-advisory: FAIL"
  exit 1
fi
