#!/usr/bin/env bash
# Tests for _shared/stack/post-merge-cleanup.sh — single subcommand.
#
# 4 cases per Sprint 3 spec §D3a:
#   - happy: mock PR MERGED, no branch/worktree errors -> exit 0 + OK line
#   - bad-args: no args -> exit 2 + Usage:
#   - refuse-not-merged: mock PR not MERGED -> exit 1 + [STOP-SAFE] + 'no MERGED PR'
#   - dry-run: SD_DRY_RUN=1, all OK -> exit 0 + 'DRY: git push origin --delete'
#
# Mock pattern (mirrors squash-merge/single-mode/test.sh fixture style):
#   SD_SKIP_REMOTE=1 skips gh + git push; refuse-not-merged case re-enables
#   the gh call by unsetting SD_SKIP_REMOTE and uses a fake gh that returns
#   empty (no merged PR found).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/stack/post-merge-cleanup.sh"

PASSED=0
FAILED=0
FAIL_NAMES=()

pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
fail() { FAILED=$((FAILED+1)); FAIL_NAMES+=("$1"); echo "  FAIL: $1 — $2"; }

# ---------------------------------------------------------------------------
# Fake gh factory — variant of squash-merge fixture style.
# Env vars:
#   FAKE_GH_MERGED  "1" -> pr list --state merged returns {"number":777}
#                   "0" or unset -> returns null (no merged PR)
# ---------------------------------------------------------------------------
make_fake_gh() {
  local bindir="$1"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  pr)
    case "$2" in
      list)
        if [[ "${FAKE_GH_MERGED:-0}" == "1" ]]; then
          echo '{"number":777}'
        else
          echo "null"
        fi
        exit 0
        ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
SHIM
  chmod +x "$bindir/gh"
}

# Build a minimal tmp git repo (real git-common-dir for flock).
make_repo() {
  local tmp="$1"
  local origin="$tmp/origin.git" work="$tmp/work"
  git init --bare -q "$origin"
  git clone -q "$origin" "$work" 2>/dev/null
  git -C "$work" config user.email t@t
  git -C "$work" config user.name t
  git -C "$work" checkout -q -b main
  echo init > "$work/README.md"
  git -C "$work" add README.md
  git -C "$work" -c commit.gpgsign=false commit -q -m initial
  git -C "$work" push -q origin main
  echo "$work"
}

# ---------------------------------------------------------------------------
# Case: bad-args -> exit 2 + Usage
# ---------------------------------------------------------------------------
test_bad_args() {
  local out rc
  out=$(bash "$SCRIPT" single 2>&1) && rc=0 || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q 'Usage:'; then
    pass "case bad-args -> exit 2 + Usage"
  else
    fail "bad-args" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: happy — SD_SKIP_REMOTE=1 (mock skip), no branch -> exit 0 + OK line
# ---------------------------------------------------------------------------
test_happy() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  local work; work=$(make_repo "$tmp")
  local out rc
  out=$( cd "$work" && SD_SKIP_REMOTE=1 \
         bash "$SCRIPT" single feat/x main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q 'OK: post-merge-cleanup single done'; then
    pass "case happy -> exit 0 + OK line"
  else
    fail "happy" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: refuse-not-merged — mock gh returns null (no MERGED PR) -> exit 1
# ---------------------------------------------------------------------------
test_refuse_not_merged() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_fake_gh "$tmp/bin"
  local work; work=$(make_repo "$tmp")
  local out rc
  # NOTE: do not set SD_SKIP_REMOTE; we want require_pr_merged to actually run.
  out=$( cd "$work" && FAKE_GH_MERGED=0 PATH="$tmp/bin:$PATH" \
         bash "$SCRIPT" single feat/x main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q 'STOP-SAFE' && \
     echo "$out" | grep -q 'no MERGED PR'; then
    pass "case refuse-not-merged -> exit 1 + STOP-SAFE + no MERGED PR"
  else
    fail "refuse-not-merged" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: dry-run — SD_DRY_RUN=1 + SD_SKIP_REMOTE=1 -> exit 0 + 'DRY:' lines
# ---------------------------------------------------------------------------
test_dry_run() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  local work; work=$(make_repo "$tmp")
  local out rc
  out=$( cd "$work" && SD_DRY_RUN=1 SD_SKIP_REMOTE=1 \
         bash "$SCRIPT" single feat/x main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q 'DRY: git push origin --delete'; then
    pass "case dry-run -> exit 0 + DRY: git push origin --delete"
  else
    fail "dry-run" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
echo "================================================="
echo " test post-merge-cleanup.sh — single subcommand"
echo "================================================="
test_bad_args
test_happy
test_refuse_not_merged
test_dry_run
echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [[ "$FAILED" -gt 0 ]]; then
  echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
