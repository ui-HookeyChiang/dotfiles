#!/usr/bin/env bash
# Tests for _shared/stack/squash-merge.sh — single subcommand.
#
# Migrated verbatim from tests/squash-merge-single/test.sh (Sprint 2 of
# unified-squash-merge rewrite). Only differences:
#   - SCRIPT points to squash-merge.sh (unified entry point)
#   - args prefixed with `single` subcommand
# All assertion logic preserved unchanged.
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
# Behaviour env vars:
#   FAKE_GH_LOG              append-only log of every gh call
#   FAKE_GH_MERGEABLE        "MERGEABLE" (default) / "DIRTY" / "CONFLICTING"
#   FAKE_GH_MSS              merge state status (default "CLEAN")
#   FAKE_GH_NO_PR            "1" -> pr list returns null
#   FAKE_GH_CHECKS_RC        rc for `gh pr checks` (default 0)
#   FAKE_GH_STATE            state for `pr view --json state` (default MERGED)
#   FAKE_GH_CHECK_COUNT      length echoed for statusCheckRollup (default 1)
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
        if [[ "${FAKE_GH_NO_PR:-0}" == "1" ]]; then
          # jq '.[0]' on empty list returns null
          echo "null"
          exit 0
        fi
        mergeable="${FAKE_GH_MERGEABLE:-MERGEABLE}"
        mss="${FAKE_GH_MSS:-CLEAN}"
        echo "{\"number\":1001,\"mergeable\":\"$mergeable\",\"mergeStateStatus\":\"$mss\"}"
        exit 0
        ;;
      view)
        jf=""
        for ((i=1;i<=$#;i++)); do [[ "${!i}" == "--json" ]] && { j=$((i+1)); jf="${!j}"; }; done
        case "$jf" in
          state) echo "${FAKE_GH_STATE:-MERGED}" ;;
          statusCheckRollup) echo "${FAKE_GH_CHECK_COUNT:-1}" ;;
          mergeStateStatus,statusCheckRollup)
            printf '{"mergeStateStatus":"%s","statusCheckRollup":%s}\n' "${FAKE_GH_MSS:-CLEAN}" "${FAKE_GH_ROLLUP:-[]}" ;;
          *) echo "main" ;;
        esac
        exit 0 ;;
      merge)  exit ${FAKE_GH_MERGE_RC:-0} ;;
      checks) exit ${FAKE_GH_CHECKS_RC:-0} ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$bindir/gh"
}

# Build a minimal tmp git repo so flock has a real git-common-dir to write into.
make_repo() {
  local tmp="$1"
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
  echo "$work"
}

# ---------------------------------------------------------------------------
# Case: bad-args-empty -> exit 2 + Usage:
# ---------------------------------------------------------------------------
test_bad_args_empty() {
  local out rc
  out=$(bash "$SCRIPT" single 2>&1) && rc=0 || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q 'Usage:'; then
    pass "case bad-args-empty -> exit 2 + Usage"
  else
    fail "bad-args-empty" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: bad-args-one -> exit 2 + Usage:
# ---------------------------------------------------------------------------
test_bad_args_one() {
  local out rc
  out=$(bash "$SCRIPT" single feat/x 2>&1) && rc=0 || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q 'Usage:'; then
    pass "case bad-args-one -> exit 2 + Usage"
  else
    fail "bad-args-one" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: happy — SD_SKIP_REMOTE=1, MERGEABLE -> exit 0 + OK line
# ---------------------------------------------------------------------------
test_happy() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  local work; work=$(make_repo "$tmp")
  local out rc
  out=$( cd "$work" && FAKE_GH_LOG="$tmp/gh.log" SD_SKIP_REMOTE=1 \
         PATH="$tmp/bin:$PATH" bash "$SCRIPT" single feat/x main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q 'OK: squash-merge-single done for'; then
    pass "case happy -> exit 0 + OK line"
  else
    fail "happy" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: pr-not-mergeable — mock DIRTY -> exit 1 + BLOCKED + not MERGEABLE
# ---------------------------------------------------------------------------
test_pr_not_mergeable() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  local work; work=$(make_repo "$tmp")
  local out rc
  out=$( cd "$work" && FAKE_GH_LOG="$tmp/gh.log" FAKE_GH_MERGEABLE=CONFLICTING FAKE_GH_MSS=DIRTY \
         SD_SKIP_REMOTE=1 PATH="$tmp/bin:$PATH" bash "$SCRIPT" single feat/x main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q 'BLOCKED: PR' && echo "$out" | grep -q 'not MERGEABLE'; then
    pass "case pr-not-mergeable -> exit 1 + BLOCKED + not MERGEABLE"
  else
    fail "pr-not-mergeable" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: pr-not-found — mock empty pr list -> exit 1 + 'no open PR found'
# ---------------------------------------------------------------------------
test_pr_not_found() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  local work; work=$(make_repo "$tmp")
  local out rc
  out=$( cd "$work" && FAKE_GH_LOG="$tmp/gh.log" FAKE_GH_NO_PR=1 \
         SD_SKIP_REMOTE=1 PATH="$tmp/bin:$PATH" bash "$SCRIPT" single feat/x main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q 'no open PR found'; then
    pass "case pr-not-found -> exit 1 + no open PR found"
  else
    fail "pr-not-found" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: ci-fail — SD_SKIP_REMOTE=0 + SD_TEST_SIMULATE_CI_FAIL=1
#   -> exit 1 + 'CI failed for PR'
# ---------------------------------------------------------------------------
test_ci_fail() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  local work; work=$(make_repo "$tmp")
  local out rc
  out=$( cd "$work" && FAKE_GH_LOG="$tmp/gh.log" SD_TEST_SIMULATE_CI_FAIL=1 \
         PATH="$tmp/bin:$PATH" bash "$SCRIPT" single feat/x main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q 'CI failed for PR'; then
    pass "case ci-fail -> exit 1 + CI failed for PR"
  else
    fail "ci-fail" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: assert-merged-fail — SD_TEST_SIMULATE_ASSERT_FAIL=1
#   (with SD_SKIP_CI_WATCH=1 so we reach the assertion step)
#   -> exit 1 + [STOP-SAFE] simulated non-MERGED
# ---------------------------------------------------------------------------
test_assert_merged_fail() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  local work; work=$(make_repo "$tmp")
  local out rc
  out=$( cd "$work" && FAKE_GH_LOG="$tmp/gh.log" \
         SD_SKIP_CI_WATCH=1 SD_TEST_SIMULATE_ASSERT_FAIL=1 \
         PATH="$tmp/bin:$PATH" bash "$SCRIPT" single feat/x main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q 'STOP-SAFE'; then
    pass "case assert-merged-fail -> exit 1 + STOP-SAFE"
  else
    fail "assert-merged-fail" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
echo "========================================="
echo " test squash-merge.sh — single subcommand"
echo "========================================="
test_bad_args_empty
test_bad_args_one
test_happy
test_pr_not_mergeable
test_pr_not_found
test_ci_fail
test_assert_merged_fail
echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [[ "$FAILED" -gt 0 ]]; then
  echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
