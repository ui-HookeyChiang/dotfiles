#!/bin/bash
# post-merge-cleanup-branch-after-worktree/test.sh
#
# F3 (run-002 dogfood): post-merge-cleanup.sh left a stale local task branch.
# Root cause (reproduced): the local `git branch -D` runs BEFORE the worktree
# holding that branch is removed. Git refuses to delete a branch checked out
# in a worktree ("cannot delete branch ... used by worktree"); the error is
# swallowed by `|| true`, so the branch lingers silently. The branch delete
# must happen AFTER worktree removal.
#
# Assertions check real git state (branch gone, worktree gone), not logs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../post-merge-cleanup.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS [$1]"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL [$1] — $2" >&2; }

gq() { git -c user.email=t@t -c user.name=t "$@"; }

make_repo() {
  local tmp="$1"
  git init --bare -q "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/work" 2>/dev/null
  cd "$tmp/work"
  git config user.email t@t; git config user.name t
  git checkout -q -b main 2>/dev/null || git checkout -q main
  echo init > README.md; gq add README.md; gq commit -q -m init
  git push -q origin main
}

# single mode: a leaf branch checked out in a worktree must be fully removed —
# BOTH the worktree directory AND the local branch — when cleanup runs from
# the repo root.
test_single_branch_and_worktree_removed() {
  local tmp rc; tmp=$(mktemp -d)
  ( make_repo "$tmp"
    cd "$tmp/work"
    gq branch feat/x/task-PR-1 main
    git worktree add -q .worktrees/x/task-PR-1 feat/x/task-PR-1
    SD_SKIP_REMOTE=1 bash "$SCRIPT" single feat/x/task-PR-1 main >/dev/null 2>&1
    [[ ! -d .worktrees/x/task-PR-1 ]] || { echo "WT-LINGERS"; exit 3; }
    if git show-ref --verify --quiet refs/heads/feat/x/task-PR-1; then echo "BRANCH-LINGERS"; exit 4; fi
  ) && rc=0 || rc=$?
  rm -rf "$tmp"
  case $rc in
    0) pass "single: worktree + local branch both removed" ;;
    3) fail "single" "worktree directory lingers after cleanup" ;;
    4) fail "single" "local branch lingers (branch -D ran before worktree removal)" ;;
    *) fail "single" "unexpected rc=$rc" ;;
  esac
}

# stack mode: same ordering hazard across Phase B (branch delete) vs Phase C
# (worktree removal). All N leaf branches + their worktrees must be gone.
test_stack_branches_and_worktrees_removed() {
  local tmp rc; tmp=$(mktemp -d)
  ( make_repo "$tmp"
    cd "$tmp/work"
    for n in 1 2; do
      gq branch "feat/x/task-${n}" main
      git worktree add -q ".worktrees/x/task-${n}" "feat/x/task-${n}"
    done
    SD_SKIP_REMOTE=1 bash "$SCRIPT" stack feat/x 2 main >/dev/null 2>&1
    for n in 1 2; do
      [[ ! -d ".worktrees/x/task-${n}" ]] || { echo "WT${n}-LINGERS"; exit 5; }
      if git show-ref --verify --quiet "refs/heads/feat/x/task-${n}"; then echo "BRANCH${n}-LINGERS"; exit 6; fi
    done
  ) && rc=0 || rc=$?
  rm -rf "$tmp"
  case $rc in
    0) pass "stack: all leaf worktrees + branches removed" ;;
    5) fail "stack" "a worktree directory lingers after cleanup" ;;
    6) fail "stack" "a local branch lingers (Phase B branch -D ran before Phase C worktree removal)" ;;
    *) fail "stack" "unexpected rc=$rc" ;;
  esac
}

echo "=== post-merge-cleanup branch-after-worktree ordering (F3) ==="
test_single_branch_and_worktree_removed
test_stack_branches_and_worktrees_removed
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
