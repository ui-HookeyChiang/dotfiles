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

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
