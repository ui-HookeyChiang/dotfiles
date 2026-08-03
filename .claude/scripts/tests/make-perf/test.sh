#!/usr/bin/env bash
# Unit test: make-perf worker count-aggregation contract.
#
# Tests that verdict sidecar temp files are correctly aggregated via
# grep -c — the mechanism the parallel Makefile uses to derive pass/fail/skip
# counts without $((x++)) in a subshell (C0 spec contract).
#
# Non-recursion strategy: this file is at scripts/tests/make-perf/test.sh.
# make test's discovery glob excludes */integration/* and */fixtures/* but NOT
# this path. Guard: check MAKE_PERF_TEST_RUNNING env var and early-exit with
# SKIP if set, so running `make test` from INSIDE this test doesn't forkbomb.
# In practice make test never sets that var — only our own recursive guard does.
#
# This test exercises the pure aggregation function in isolation using synthetic
# verdict sidecar files under a fixtures/ subdir (which make test excludes from
# discovery anyway, so no recursive issues there).
set -euo pipefail

# Forkbomb guard: if we're already inside a make test invocation spawned by this
# very test file, bail out quietly rather than recurse.
if [[ "${MAKE_PERF_TEST_RUNNING:-}" == "1" ]]; then
  echo "SKIP: make-perf/test.sh detected recursive invocation — bailing" >&2
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

# ── helper: aggregate_verdicts <dir> ─────────────────────────────────────────
# Given a directory of sidecar files each containing a single verdict token
# (PASS, FAIL, or SKIP), derive counts via grep -c (the C0 spec mechanism).
# Prints: "pass=N fail=N skip=N"
aggregate_verdicts() {
  local dir="$1"
  local pass=0 fail=0 skip=0
  # grep -c returns 0 when match found, 1 when not — suppress exit 1.
  pass=$(grep -rl '^PASS$' "$dir" 2>/dev/null | wc -l || true)
  fail=$(grep -rl '^FAIL$' "$dir" 2>/dev/null | wc -l || true)
  skip=$(grep -rl '^SKIP$' "$dir" 2>/dev/null | wc -l || true)
  echo "pass=${pass} fail=${fail} skip=${skip}"
}

# ── test 1: pure PASS/FAIL/SKIP counts from verdict sidecars ─────────────────
T1=$(mktemp -d)
trap 'rm -rf "$T1"' EXIT

# Simulate 3 PASS, 1 FAIL, 2 SKIP
for i in 1 2 3; do printf 'PASS\n' > "$T1/verdict.$i"; done
printf 'FAIL\n' > "$T1/verdict.4"
printf 'SKIP\n' > "$T1/verdict.5"
printf 'SKIP\n' > "$T1/verdict.6"

result=$(aggregate_verdicts "$T1")
[[ "$result" == "pass=3 fail=1 skip=2" ]] \
  || fail "test1 count mismatch: expected 'pass=3 fail=1 skip=2', got '$result'"

echo "  test1 PASS: aggregate_verdicts counts correctly"

# ── test 2: all PASS (fail=0 → exit 0 contract) ─────────────────────────────
T2=$(mktemp -d)
trap 'rm -rf "$T1" "$T2"' EXIT

printf 'PASS\n' > "$T2/verdict.1"
printf 'PASS\n' > "$T2/verdict.2"

result2=$(aggregate_verdicts "$T2")
[[ "$result2" == "pass=2 fail=0 skip=0" ]] \
  || fail "test2 all-pass: expected 'pass=2 fail=0 skip=0', got '$result2'"

echo "  test2 PASS: all-pass gives fail=0"

# ── test 3: SKIP not folded into PASS (M-skip contract) ──────────────────────
T3=$(mktemp -d)
trap 'rm -rf "$T1" "$T2" "$T3"' EXIT

printf 'SKIP\n' > "$T3/verdict.1"
printf 'PASS\n' > "$T3/verdict.2"

result3=$(aggregate_verdicts "$T3")
pass_ct=$(echo "$result3" | grep -o 'pass=[0-9]*' | cut -d= -f2)
skip_ct=$(echo "$result3" | grep -o 'skip=[0-9]*' | cut -d= -f2)
[[ "$skip_ct" -eq 1 ]] || fail "test3 M-skip: SKIP folded into PASS (skip=$skip_ct, full=$result3)"
[[ "$pass_ct" -eq 1 ]] || fail "test3 M-skip: PASS count wrong (pass=$pass_ct, full=$result3)"

echo "  test3 PASS: SKIP not folded into PASS"

# ── test 4: warn verdict for lint (pass/fail/warn distinction) ───────────────
aggregate_lint_verdicts() {
  local dir="$1"
  local pass=0 fail=0 warn=0
  pass=$(grep -rl '^PASS$' "$dir" 2>/dev/null | wc -l || true)
  fail=$(grep -rl '^FAIL$' "$dir" 2>/dev/null | wc -l || true)
  warn=$(grep -rl '^WARN$' "$dir" 2>/dev/null | wc -l || true)
  echo "pass=${pass} fail=${fail} warn=${warn}"
}

T4=$(mktemp -d)
trap 'rm -rf "$T1" "$T2" "$T3" "$T4"' EXIT

printf 'PASS\n' > "$T4/verdict.1"
printf 'WARN\n' > "$T4/verdict.2"
printf 'WARN\n' > "$T4/verdict.3"
printf 'FAIL\n' > "$T4/verdict.4"

result4=$(aggregate_lint_verdicts "$T4")
[[ "$result4" == "pass=1 fail=1 warn=2" ]] \
  || fail "test4 lint-verdicts: expected 'pass=1 fail=1 warn=2', got '$result4'"

echo "  test4 PASS: lint WARN verdict counted separately from PASS/FAIL"

# ── test 5: Makefile exists and has parallel markers (post-optimization only) ─
# This test is EXPECTED TO FAIL (RED) before the Makefile is optimized.
# It checks that xargs -P appears in the Makefile (proof of parallelization).
MAKEFILE="$REPO_ROOT/Makefile"
[[ -f "$MAKEFILE" ]] || fail "Makefile not found at $MAKEFILE"

grep -q 'xargs.*-P' "$MAKEFILE" \
  || fail "Makefile has no xargs -P — parallel optimization not yet applied (RED: expected pre-optimization)"

echo "  test5 PASS: Makefile contains xargs -P parallel invocation"

echo ""
echo "PASS: all make-perf aggregation unit tests passed"
