#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/stack/merge-train.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"
git init -q -b main main
cd main
echo "base" > base.txt
git -c user.email=t@t -c user.name=t add base.txt
git -c user.email=t@t -c user.name=t commit -q -m "base"

# Build 3 file-disjoint leaf branches
for g in PR-1 PR-2 PR-3; do
  git -c user.email=t@t -c user.name=t branch "feat/foo/task-${g}" main
  git worktree add ".worktrees/feat-foo/task-${g}" "feat/foo/task-${g}" 2>/dev/null
  case "$g" in
    PR-1) f=foo.txt ;;
    PR-2) f=bar.txt ;;
    PR-3) f=baz.txt ;;
  esac
  echo "$g" > ".worktrees/feat-foo/task-${g}/$f"
  (cd ".worktrees/feat-foo/task-${g}" && \
    git -c user.email=t@t -c user.name=t add "$f" && \
    git -c user.email=t@t -c user.name=t commit -q -m "feat: add $f")
done

# Test 1: clean merge-train succeeds, all 3 files end up in integration HEAD
LAYERS='[["PR-1"],["PR-2","PR-3"]]'
SD_PARALLEL_LAYERS="$LAYERS" \
  bash "$SCRIPT" \
    --feature-prefix "feat/foo" \
    --worktree-ns "feat-foo" \
    --default-branch "main"

INT=".worktrees/feat-foo/integration"
for f in foo.txt bar.txt baz.txt; do
  if ! git -C "$INT" cat-file -e "HEAD:$f" 2>/dev/null; then
    echo "FAIL: $f not in integration HEAD" >&2
    exit 1
  fi
done
echo "PASS [3 leaves merged into integration]"

# Test 2: re-running clean state is idempotent (no error, same result)
SD_PARALLEL_LAYERS="$LAYERS" \
  bash "$SCRIPT" \
    --feature-prefix "feat/foo" \
    --worktree-ns "feat-foo" \
    --default-branch "main"
echo "PASS [idempotent rerun on clean state]"

# Test 3 (Amendment A6): mid-rebase state must NOT be silently wiped.
INT_GITDIR=$(git -C "$INT" rev-parse --git-dir)
mkdir -p "$INT_GITDIR/rebase-merge"
echo "marker" > "$INT_GITDIR/rebase-merge/head-name"

set +e
OUT=$(SD_PARALLEL_LAYERS="$LAYERS" \
  bash "$SCRIPT" \
    --feature-prefix "feat/foo" \
    --worktree-ns "feat-foo" \
    --default-branch "main" 2>&1)
RC=$?
set -e

if [[ $RC -eq 0 ]]; then
  echo "FAIL: merge-train should have refused on mid-rebase state" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "STOP-SAFE.*rebase"; then
  echo "FAIL: STOP-SAFE rebase message expected, got: $OUT" >&2
  exit 1
fi
echo "PASS [A6: mid-rebase state refused]"

rm -rf "$INT_GITDIR/rebase-merge"

# Test 4 (I1): empty parallel_layers must STOP-SAFE
set +e
OUT=$(SD_PARALLEL_LAYERS='[]' \
  bash "$SCRIPT" \
    --feature-prefix "feat/foo" \
    --worktree-ns "feat-foo" \
    --default-branch "main" 2>&1)
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  echo "FAIL: empty parallel_layers should have refused" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "parallel_layers is empty"; then
  echo "FAIL: expected empty-layers error message, got: $OUT" >&2
  exit 1
fi
echo "PASS [I1: empty parallel_layers refused]"

# Test 5 (M1): WORKTREE_NS path traversal must STOP-SAFE
set +e
OUT=$(SD_PARALLEL_LAYERS='[["PR-1"]]' \
  bash "$SCRIPT" \
    --feature-prefix "feat/foo" \
    --worktree-ns "../escape" \
    --default-branch "main" 2>&1)
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  echo "FAIL: path-traversal WORKTREE_NS should have refused" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "invalid --worktree-ns"; then
  echo "FAIL: expected WORKTREE_NS validation error, got: $OUT" >&2
  exit 1
fi
echo "PASS [M1: WORKTREE_NS path-traversal refused]"

# Test 6 (Tier 1 dogfood finding): stale integration branch with worktree
# already removed by operator must not block recovery. The A6 STOP-SAFE
# message instructs the operator to `git worktree remove --force $INT_DIR`
# but does NOT mention deleting the branch. Without this cleanup,
# the next merge-train.sh invocation fails with
# "fatal: a branch named '...' already exists".
LAYERS='[["PR-1"],["PR-2","PR-3"]]'
# Recreate a clean integration worktree first
SD_PARALLEL_LAYERS="$LAYERS" \
  bash "$SCRIPT" \
    --feature-prefix "feat/foo" \
    --worktree-ns "feat-foo" \
    --default-branch "main" >/dev/null
# Operator removes worktree but leaves the branch (simulates A6 abort path)
INT=".worktrees/feat-foo/integration"
git worktree remove --force "$INT" 2>/dev/null
# Verify the branch is still around (stale)
if ! git rev-parse --verify "feat/foo/integration" >/dev/null 2>&1; then
  echo "FAIL: integration branch should still exist (worktree-remove only nukes the worktree)" >&2
  exit 1
fi
# Next invocation must clean the stale branch and succeed
SD_PARALLEL_LAYERS="$LAYERS" \
  bash "$SCRIPT" \
    --feature-prefix "feat/foo" \
    --worktree-ns "feat-foo" \
    --default-branch "main" >/dev/null
if [[ ! -d "$INT" ]]; then
  echo "FAIL: merge-train did not recreate integration worktree after stale-branch cleanup" >&2
  exit 1
fi
echo "PASS [stale integration branch recovery]"

echo "All tests passed"
