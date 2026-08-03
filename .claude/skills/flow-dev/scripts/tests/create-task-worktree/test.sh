#!/usr/bin/env bash
# Tests for flow-dev/scripts/create-task-worktree.sh
# Covers: linear mode (task 1, task 2), parallel mode (layer 1),
#         STOP-SAFE (empty array, missing GROUP_ID)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SCRIPT="$REPO_ROOT/flow-dev/scripts/create-task-worktree.sh"

PASSED=0
FAILED=0
pass() { ((PASSED++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); echo "  FAIL: $1" >&2; }

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

setup_repo() {
  local dir="$TMPDIR_ROOT/$1"
  mkdir -p "$dir"
  (cd "$dir" && git init -b main --quiet && git commit --allow-empty -m "init" --quiet)
  local bare="$TMPDIR_ROOT/${1}-bare"
  git clone --bare --quiet "$dir" "$bare" 2>/dev/null
  (cd "$dir" && git remote remove origin 2>/dev/null; git remote add origin "$bare"
   git fetch origin --quiet 2>/dev/null)
  echo "$dir"
}

# --- Case 1: linear mode, task 1 (base = default branch) ---
echo "Case 1: linear mode, task 1"
REPO=$(setup_repo case1)
out=$(cd "$REPO" && bash "$SCRIPT" feat/foo 1 main ns-foo 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] \
  && echo "$out" | grep -q 'WORKTREE_DIR=.worktrees/ns-foo/task-1' \
  && echo "$out" | grep -q 'TASK_BRANCH=feat/foo/task-1' \
  && echo "$out" | grep -q 'BASE_BRANCH=main'; then
  pass "linear task-1 outputs correct"
else
  fail "linear task-1: rc=$rc out=$out"
fi
if [[ -d "$REPO/.worktrees/ns-foo/task-1" ]]; then
  pass "worktree created"
else
  fail "worktree not found"
fi

# --- Case 2: linear mode, task 2 (base = task-1 branch) ---
echo "Case 2: linear mode, task 2"
REPO=$(setup_repo case2)
(cd "$REPO" && bash "$SCRIPT" feat/bar 1 main ns-bar >/dev/null 2>&1
 git push origin feat/bar/task-1 --quiet 2>/dev/null)
out=$(cd "$REPO" && bash "$SCRIPT" feat/bar 2 main ns-bar 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] \
  && echo "$out" | grep -q 'TASK_BRANCH=feat/bar/task-2' \
  && echo "$out" | grep -q 'BASE_BRANCH=feat/bar/task-1'; then
  pass "linear task-2 bases on task-1"
else
  fail "linear task-2: rc=$rc out=$out"
fi

# --- Case 3: STOP-SAFE on empty parallel_layers array ---
echo "Case 3: STOP-SAFE empty parallel_layers"
REPO=$(setup_repo case3)
(cd "$REPO" && echo '{"parallel_layers": []}' > .flow-dev-lock)
out=$(cd "$REPO" && bash "$SCRIPT" feat/baz 1 main ns-baz 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'STOP-SAFE.*empty array'; then
  pass "empty array STOP-SAFE fires"
else
  fail "empty array: rc=$rc out=$out"
fi

# --- Case 4: STOP-SAFE on missing GROUP_ID ---
echo "Case 4: STOP-SAFE missing GROUP_ID"
REPO=$(setup_repo case4)
(cd "$REPO" && echo '{"parallel_layers": [["PR-1"],["PR-2"]]}' > .flow-dev-lock)
out=$(cd "$REPO" && SD_GROUP_ID="PR-999" bash "$SCRIPT" feat/qux 1 main ns-qux 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'STOP-SAFE.*GROUP_ID'; then
  pass "missing GROUP_ID STOP-SAFE fires"
else
  fail "missing GROUP_ID: rc=$rc out=$out"
fi

# --- Case 5: parallel mode, layer 1 (base = default branch) ---
echo "Case 5: parallel mode, layer 1"
REPO=$(setup_repo case5)
(cd "$REPO" && echo '{"parallel_layers": [["PR-1"],["PR-2"]]}' > .flow-dev-lock)
out=$(cd "$REPO" && SD_GROUP_ID="PR-1" bash "$SCRIPT" feat/par 1 main ns-par 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] \
  && echo "$out" | grep -q 'TASK_BRANCH=feat/par/task-PR-1' \
  && echo "$out" | grep -q 'BASE_BRANCH=main'; then
  pass "parallel layer-1 bases on default branch"
else
  fail "parallel layer-1: rc=$rc out=$out"
fi

# --- Case 6: origin ref exists → worktree based on origin/BASE_BRANCH ---
# Uses eval to catch stdout corruption (git progress lines would break the eval contract).
echo "Case 6: origin ref exists"
REPO=$(setup_repo case6)
eval_out=$(cd "$REPO" && eval "$(bash "$SCRIPT" feat/c6 1 main ns-c6 2>/dev/null)" && echo "WORKTREE_DIR=$WORKTREE_DIR TASK_BRANCH=$TASK_BRANCH BASE_BRANCH=$BASE_BRANCH") && eval_rc=0 || eval_rc=$?
if [[ "$eval_rc" -eq 0 ]] \
  && echo "$eval_out" | grep -q 'WORKTREE_DIR=.worktrees/ns-c6/task-1' \
  && echo "$eval_out" | grep -q 'TASK_BRANCH=feat/c6/task-1' \
  && echo "$eval_out" | grep -q 'BASE_BRANCH=main'; then
  pass "origin exists: eval contract clean, outputs correct"
else
  fail "origin exists: eval_rc=$eval_rc eval_out=$eval_out"
fi
if [[ -d "$REPO/.worktrees/ns-c6/task-1" ]]; then
  pass "origin exists: worktree directory present"
else
  fail "origin exists: worktree directory missing"
fi

# --- Case 7: origin ref missing + local unpushed → STOP-SAFE exit 1 ---
echo "Case 7: origin ref missing + local base unpushed"
REPO=$(setup_repo case7)
# Create an extra local branch that has never been pushed to origin
(cd "$REPO" && git checkout -b feat/unpushed --quiet && git commit --allow-empty -m "local only" --quiet && git checkout main --quiet)
out=$(cd "$REPO" && bash "$SCRIPT" feat/c7 1 feat/unpushed ns-c7 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -qi 'STOP-SAFE'; then
  pass "local-only unpushed: STOP-SAFE exit 1"
else
  fail "local-only unpushed: rc=$rc out=$out"
fi
if [[ ! -d "$REPO/.worktrees/ns-c7/task-1" ]]; then
  pass "local-only unpushed: no worktree created"
else
  fail "local-only unpushed: worktree was created (should not be)"
fi

# --- Case 8: origin ref missing + local SHA == upstream SHA → proceed ---
echo "Case 8: origin ref missing + local SHA == upstream SHA"
REPO=$(setup_repo case8)
# Push a branch so it's on origin, then remove the remote-tracking ref locally.
# rev-parse --verify origin/feat/synced now fails (no local tracking ref), but
# ls-remote still sees it on the bare remote and SHAs match — script should proceed.
(cd "$REPO" && git checkout -b feat/synced --quiet && git commit --allow-empty -m "synced" --quiet
 git push origin feat/synced --quiet 2>/dev/null
 git update-ref -d refs/remotes/origin/feat/synced)
out=$(cd "$REPO" && bash "$SCRIPT" feat/c8 1 feat/synced ns-c8 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "synced-upstream: proceeds when local SHA == upstream SHA"
else
  fail "synced-upstream: rc=$rc out=$out"
fi

# --- Case 9: worktree-add hard failure surfaces git's real error ---
echo "Case 9: worktree-add failure surfaces git error"
REPO=$(setup_repo case9)
# Pre-register a worktree at the target path manually so git worktree add fails
# with its own "already exists" error. The script must NOT suppress stderr (no
# 2>/dev/null), so the git message must appear in stderr-captured output.
(cd "$REPO" && bash "$SCRIPT" feat/c9pre 1 main ns-c9 >/dev/null 2>&1 || true)
# Now the path .worktrees/ns-c9/task-1 already exists; running again for task-1
# reuses the same WORKTREE_DIR (the script does rm -rf first, so we need to
# also pre-register the branch in git's worktree list to trigger the add failure).
# Simplest path: create a locked worktree entry so prune won't clean it up, and
# the directory already exists — rm -rf removes it but git worktree add will fail
# because the task branch already exists as a checked-out worktree branch.
# Actually: after rm -rf the dir, git worktree add -b $BRANCH fails if $BRANCH
# is currently checked out in another worktree. Register that condition:
WDIR="$REPO/.worktrees/ns-c9/task-1"
mkdir -p "$WDIR"
# Write a fake .git file so git sees this as an existing worktree checkout path
echo "gitdir: $REPO/.git/worktrees/fake" > "$WDIR/.git"
mkdir -p "$REPO/.git/worktrees/fake"
printf 'gitdir: %s/.git/worktrees/fake\n' "$REPO" > "$REPO/.git/worktrees/fake/gitdir"
printf '%s\n' "$WDIR" > "$REPO/.git/worktrees/fake/gitdir"
# Prevent prune from removing the entry by adding a 'locked' file
echo "kept for test" > "$REPO/.git/worktrees/fake/locked"
# Point HEAD at the branch the script would try to create, so worktree add -b fails
echo "ref: refs/heads/feat/c9/task-1" > "$REPO/.git/worktrees/fake/HEAD"
out=$(cd "$REPO" && bash "$SCRIPT" feat/c9 1 main ns-c9 2>&1) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]] && echo "$out" | grep -qiE 'fatal|error'; then
  pass "hard failure: git error surfaces, exits non-zero"
else
  fail "hard failure: rc=$rc out=$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
