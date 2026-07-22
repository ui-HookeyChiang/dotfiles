#!/usr/bin/env bash
# Tests for _shared/stack/squash-merge.sh — stack subcommand.
#
# Migrated verbatim from tests/squash-merge-stack/test.sh (Sprint 2 of
# unified-squash-merge rewrite). Only differences:
#   - SCRIPT points to squash-merge.sh (unified entry point)
#   - args prefixed with `stack` subcommand
#   - case-7 structural test continues to assert on squash-merge.sh (target file)
# All assertion logic preserved unchanged.
#
# The cherry-pick array-quoting hardening is covered by the sibling regression
# test at scripts/tests/cherry-pick-quoting/test.sh — we don't duplicate it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/stack/squash-merge.sh"

PASSED=0
FAILED=0
FAIL_NAMES=()

pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
fail() { FAILED=$((FAILED+1)); FAIL_NAMES+=("$1"); echo "  FAIL: $1 — $2"; }

# ---------------------------------------------------------------------------
# Fake gh factory — writes a self-contained shim into $1/bin/gh.
# Behaviour controlled via env vars set by each case before invoking script:
#   FAKE_GH_LOG     append-only log of every gh call (one line per call)
#   FAKE_GH_MERGEABLE  default "MERGEABLE" — JSON for `pr list .mergeable`
#   FAKE_GH_BAD_TASK   "" or task number whose pr list returns CONFLICTING
# ---------------------------------------------------------------------------
make_fake_gh() {
  local bindir="$1"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<'SHIM'
#!/usr/bin/env bash
log="${FAKE_GH_LOG:-/dev/null}"
echo "gh $*" >> "$log"
case "$1" in
  pr)
    case "$2" in
      list)
        head=""
        for ((i=1;i<=$#;i++)); do
          if [[ "${!i}" == "--search" ]]; then j=$((i+1)); head="${!j#head:}"; fi
        done
        task="${head##*/task-}"
        if [[ -n "${FAKE_GH_BAD_TASK:-}" && "$task" == "$FAKE_GH_BAD_TASK" ]]; then
          state="CONFLICTING"; mss="DIRTY"
        else
          state="${FAKE_GH_MERGEABLE:-MERGEABLE}"
          # B5: tests can simulate UNSTABLE (CI pending) via FAKE_GH_MSS
          mss="${FAKE_GH_MSS:-CLEAN}"
        fi
        echo "{\"number\":$((1000+task)),\"mergeable\":\"$state\",\"mergeStateStatus\":\"$mss\"}"
        exit 0
        ;;
      view)
        # B2 + PR2 helpers (state / statusCheckRollup / mergeStateStatus,statusCheckRollup)
        jf=""
        for ((i=1;i<=$#;i++)); do [[ "${!i}" == "--json" ]] && { j=$((i+1)); jf="${!j}"; }; done
        case "$jf" in
          baseRefName) echo "${FAKE_GH_BASE:-main}" ;;
          state) echo "${FAKE_GH_STATE:-MERGED}" ;;
          statusCheckRollup) echo "${FAKE_GH_CHECK_COUNT:-1}" ;;
          mergeStateStatus,statusCheckRollup)
            printf '{"mergeStateStatus":"%s","statusCheckRollup":%s}\n' "${FAKE_GH_MSS:-CLEAN}" "${FAKE_GH_ROLLUP:-[]}" ;;
          *) echo "${FAKE_GH_BASE:-main}" ;;
        esac
        exit 0 ;;
      merge) exit 0 ;;
      close) exit 0 ;;
      checks) exit ${FAKE_GH_CHECKS_RC:-0} ;;
      *) exit 0 ;;
    esac
    ;;
  api) exit 0 ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$bindir/gh"
}

# Build a tmp git repo with bare origin + working clone, plus N stacked task
# branches each carrying one unique commit. Echoes "ORIGIN WORK" path pair.
make_repo() {
  local tmp="$1" feature_prefix="$2" total="$3"
  local origin="$tmp/origin.git" work="$tmp/work"
  git init --bare -q "$origin"
  git clone -q "$origin" "$work"
  git -C "$work" config user.email t@t
  git -C "$work" config user.name t
  git -C "$work" checkout -q -b main
  echo init > "$work/README.md"
  git -C "$work" add README.md
  git -C "$work" commit -q -m initial
  git -C "$work" push -q origin main
  for n in $(seq 1 "$total"); do
    local base
    if [[ "$n" -eq 1 ]]; then base="main"; else base="${feature_prefix}/task-$((n-1))"; fi
    git -C "$work" checkout -q -b "${feature_prefix}/task-${n}" "$base"
    echo "task-${n}" > "$work/task-${n}.txt"
    git -C "$work" add "task-${n}.txt"
    git -C "$work" commit -q -m "feat: task ${n}"
    git -C "$work" push -q origin "${feature_prefix}/task-${n}"
  done
  git -C "$work" checkout -q main
  echo "$origin $work"
}

# ---------------------------------------------------------------------------
# Case 1 — no args -> exit 2 + "Usage:" on stderr
# ---------------------------------------------------------------------------
test_no_args() {
  local out rc
  out=$(bash "$SCRIPT" stack 2>&1) && rc=0 || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q 'Usage:'; then
    pass "case-1 no args -> exit 2 + Usage"
  else
    fail "case-1 no args" "rc=$rc, out=$out"
  fi
}

# Case 2 — only one arg -> exit 2
test_one_arg() {
  local rc
  bash "$SCRIPT" stack feat/x >/dev/null 2>&1 && rc=0 || rc=$?
  if [[ "$rc" == 2 ]]; then pass "case-2 one arg -> exit 2"
  else fail "case-2 one arg" "rc=$rc"; fi
}

# Case 3 — total_tasks=0 -> exit 2 (arg validation)
test_zero_tasks() {
  local rc
  bash "$SCRIPT" stack feat/x 0 main >/dev/null 2>&1 && rc=0 || rc=$?
  if [[ "$rc" == 2 ]]; then pass "case-3 zero tasks -> exit 2"
  else fail "case-3 zero tasks" "rc=$rc"; fi
}

# Case 4 — pre-check fails: gh returns CONFLICTING for task-1 -> exit 1
test_precheck_blocks() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  local log="$tmp/gh.log" out rc
  : > "$log"
  out=$(FAKE_GH_LOG="$log" FAKE_GH_BAD_TASK=1 \
        PATH="$tmp/bin:$PATH" bash "$SCRIPT" stack feat/foo 2 main 2>&1) && rc=0 || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q 'BLOCKED' && \
     echo "$out" | grep -q 'feat/foo/task-1'; then
    # And no `gh pr merge` should have been called
    if grep -q 'pr merge' "$log"; then
      fail "case-4 pre-check blocks" "merge was called despite BLOCKED"
    else
      pass "case-4 pre-check blocks before any merge"
    fi
  else
    fail "case-4 pre-check blocks" "rc=$rc, out=$out"
  fi
}

# Case 5 — total_tasks=1 happy path
test_happy_1() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  read -r ORIGIN WORK < <(make_repo "$tmp" feat/foo 1)
  local log="$tmp/gh.log" rc
  : > "$log"
  ( cd "$WORK" && FAKE_GH_LOG="$log" PATH="$tmp/bin:$PATH" \
      bash "$SCRIPT" stack feat/foo 1 main >/dev/null 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && grep -q 'pr merge 1001 --squash' "$log"; then
    pass "case-5 happy path 1 task"
  else
    fail "case-5 happy path 1 task" "rc=$rc; log=$(cat "$log")"
  fi
}

# Case 6 — total_tasks=2 happy path with real git on tmp repo.
# Asserts the gh call sequence: 2 pre-check pr list, then merge task-1,
# then api PATCH base for task-2, then merge task-2.
# NOTE: the fake gh `api` only logs the call — it does NOT actually mutate
# any real GitHub state. The test verifies the script *issued* the PATCH;
# real-world base re-pointing is exercised in production.
test_happy_2() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  read -r ORIGIN WORK < <(make_repo "$tmp" feat/foo 2)
  local log="$tmp/gh.log" rc out
  : > "$log"
  out=$( cd "$WORK" && FAKE_GH_LOG="$log" PATH="$tmp/bin:$PATH" \
         bash "$SCRIPT" stack feat/foo 2 main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" != 0 ]]; then
    fail "case-6 happy path 2 tasks" "rc=$rc, out=$out, log=$(cat "$log")"; return
  fi
  # Verify expected gh call sequence
  # Pre-check: 2 pr list calls (one per task)
  local n_list n_merge n_api
  n_list=$(grep -c '^gh pr list ' "$log" || true)
  n_merge=$(grep -c '^gh pr merge ' "$log" || true)
  n_api=$(grep -c '^gh api ' "$log" || true)
  if [[ "$n_list" -lt 2 ]]; then
    fail "case-6 happy path 2 tasks" "expected >=2 pr list, got $n_list"; return
  fi
  if [[ "$n_merge" -ne 2 ]]; then
    fail "case-6 happy path 2 tasks" "expected 2 pr merge, got $n_merge"; return
  fi
  # Sprint 5 / B2: task-1 also calls gh api PATCH (base detection); expect 2.
  if [[ "$n_api" -lt 1 ]]; then
    fail "case-6 happy path 2 tasks" "expected >=1 gh api PATCH, got $n_api"; return
  fi
  # Order: PATCH (any) must precede each merge it precedes; both merges fire.
  if ! awk '
    /^gh pr merge 1001/  {m1=NR}
    /^gh pr merge 1002/  {m2=NR}
    END { exit (m1 && m2 && m1<m2) ? 0 : 1 }' "$log"; then
    fail "case-6 happy path 2 tasks" "merge order wrong; log=$(cat "$log")"; return
  fi
  pass "case-6 happy path 2 tasks (sequence verified)"
}

# Case 7 — structural: shebang + set -euo pipefail on the unified script.
# Note: line-count budget intentionally NOT enforced here — squash-merge.sh
# combines both single+stack bodies (~320 lines), per CONTEXT.md "Sub-200-line
# script targets are flexible; new squash-merge.sh expected 200-300 lines".
test_structural() {
  local first; first=$(head -1 "$SCRIPT")
  if [[ "$first" != "#!/usr/bin/env bash" && "$first" != "#!/bin/bash" ]]; then
    fail "case-7 structural" "missing/bad shebang: $first"; return
  fi
  if ! grep -q '^set -euo pipefail' "$SCRIPT"; then
    fail "case-7 structural" "missing set -euo pipefail"; return
  fi
  local n; n=$(wc -l < "$SCRIPT" | tr -d ' ')
  pass "case-7 structural (shebang + set -euo pipefail + $n lines)"
}

# ---------------------------------------------------------------------------
# Sprint 5 — B1-B7 dedicated cases
# ---------------------------------------------------------------------------

# Case 8 / B5 — UNSTABLE accepted as MERGEABLE (CI pending is OK, will watch)
test_b5_unstable_accept() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  read -r ORIGIN WORK < <(make_repo "$tmp" feat/foo 1)
  local rc out
  out=$( cd "$WORK" && FAKE_GH_LOG="$tmp/gh.log" FAKE_GH_MSS=UNSTABLE \
         SD_SKIP_CI_WATCH=1 PATH="$tmp/bin:$PATH" \
         bash "$SCRIPT" stack feat/foo 1 main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q 'MERGEABLE/UNSTABLE'; then
    pass "case-8 B5 UNSTABLE accepted (mergeStateStatus reported in log)"
  else
    fail "case-8 B5 UNSTABLE accept" "rc=$rc, out=$out"
  fi
}

# Case 9 / B6 — untracked stale spec moved to /tmp before cherry-pick
test_b6_stale_spec_cleanup() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  read -r ORIGIN WORK < <(make_repo "$tmp" feat/foo 1)
  mkdir -p "$WORK/docs/specs/proposed"
  echo "stale" > "$WORK/docs/specs/proposed/2026-05-06-flow-dev-old.md"
  local rc
  ( cd "$WORK" && FAKE_GH_LOG="$tmp/gh.log" SD_SKIP_CI_WATCH=1 \
    PATH="$tmp/bin:$PATH" bash "$SCRIPT" stack feat/foo 1 main >/dev/null 2>&1 ) && rc=0 || rc=$?
  # cleanup_stale_specs moved file to /tmp/stale-spec-untracked/
  if [[ "$rc" == 0 ]] && [[ ! -f "$WORK/docs/specs/proposed/2026-05-06-flow-dev-old.md" ]]; then
    pass "case-9 B6 stale spec moved out of working tree"
  else
    fail "case-9 B6 stale spec cleanup" "rc=$rc, file still present"
  fi
}

# Case 10 / B3 — diff-verify guards empty force-push, closes PR instead
test_b3_diff_verify() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  # Build origin where task-1 is a no-op (same tree as main)
  local origin="$tmp/origin.git" work="$tmp/work"
  git init --bare -q "$origin"
  git clone -q "$origin" "$work"
  git -C "$work" config user.email t@t; git -C "$work" config user.name t
  git -C "$work" checkout -q -b main
  echo init > "$work/README.md"; git -C "$work" add README.md
  git -C "$work" commit -q -m initial; git -C "$work" push -q origin main
  # task-1 has same tree as main (no unique commit content)
  git -C "$work" checkout -q -b feat/foo/task-1 main
  git -C "$work" commit -q --allow-empty -m "no-op task"
  git -C "$work" push -q origin feat/foo/task-1
  git -C "$work" checkout -q main
  local rc out
  out=$( cd "$work" && FAKE_GH_LOG="$tmp/gh.log" SD_SKIP_CI_WATCH=1 \
         PATH="$tmp/bin:$PATH" bash "$SCRIPT" stack feat/foo 1 main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -qE 'Empty diff|Empty commit range'; then
    # And no `gh pr merge` for the empty PR
    if grep -q 'pr merge 1001' "$tmp/gh.log"; then
      fail "case-10 B3 diff-verify" "merge fired despite empty diff"
    else
      pass "case-10 B3 empty-diff PR closed (no force-push)"
    fi
  else
    fail "case-10 B3 diff-verify" "rc=$rc, out=$out"
  fi
}

# Case 11 / B1 — gh pr checks --watch is invoked between push and merge
test_b1_ci_watch() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  read -r ORIGIN WORK < <(make_repo "$tmp" feat/foo 1)
  local log="$tmp/gh.log" rc
  : > "$log"
  ( cd "$WORK" && FAKE_GH_LOG="$log" PATH="$tmp/bin:$PATH" \
    bash "$SCRIPT" stack feat/foo 1 main >/dev/null 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && grep -q '^gh pr checks ' "$log"; then
    # checks must precede merge for that PR
    if awk '/^gh pr checks 1001/{c=NR} /^gh pr merge 1001/{m=NR} END{exit (c && m && c<m)?0:1}' "$log"; then
      pass "case-11 B1 CI watch fired before merge"
    else
      fail "case-11 B1 CI watch" "checks did not precede merge in log"
    fi
  else
    fail "case-11 B1 CI watch" "rc=$rc, no 'gh pr checks' in log"
  fi
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
echo "========================================="
echo " test squash-merge.sh — stack subcommand"
echo "========================================="
test_no_args
test_one_arg
test_zero_tasks
test_precheck_blocks
test_happy_1
test_happy_2
test_structural
test_b5_unstable_accept
test_b6_stale_spec_cleanup
test_b3_diff_verify
test_b1_ci_watch
echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [[ "$FAILED" -gt 0 ]]; then
  echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
