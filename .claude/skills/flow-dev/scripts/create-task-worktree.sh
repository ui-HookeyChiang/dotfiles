#!/bin/bash
# create-task-worktree.sh — resolve BASE_BRANCH (linear/parallel), create worktree.
# Usage: create-task-worktree.sh <feature_prefix> <task_n> <default_branch> <worktree_ns>
# Env: SD_GROUP_ID (parallel mode override for task identifier)
# Outputs (eval-able): WORKTREE_DIR=... TASK_BRANCH=... BASE_BRANCH=...
# Exit: 0=ok, 1=STOP-SAFE (lock corruption / GROUP_ID not found)

set -euo pipefail

FEATURE_PREFIX="${1:?Usage: create-task-worktree.sh <feature_prefix> <task_n> <default_branch> <worktree_ns>}"
N="${2:?missing task_n}"
DEFAULT_BRANCH="${3:?missing default_branch}"
WORKTREE_NS="${4:?missing worktree_ns}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../_shared/stack/lib/parallel-layers.sh
[[ -f "$REPO_ROOT/_shared/stack/lib/parallel-layers.sh" ]] \
  && . "$REPO_ROOT/_shared/stack/lib/parallel-layers.sh"

LOCK_LAYERS=$(jq -c '.parallel_layers // null' .flow-dev-lock 2>/dev/null || echo null)
if [[ "$LOCK_LAYERS" == "null" ]]; then
  [[ "$N" -eq 1 ]] && BASE_BRANCH="$DEFAULT_BRANCH" || BASE_BRANCH="${FEATURE_PREFIX}/task-$((N-1))"
  TASK_BRANCH="${FEATURE_PREFIX}/task-${N}"
else
  if [[ "$LOCK_LAYERS" == "[]" ]]; then
    echo "[STOP-SAFE] .flow-dev-lock.parallel_layers is empty array — lock corruption." >&2
    exit 1
  fi
  if ! type pl_layer_of >/dev/null 2>&1; then
    echo "[STOP-SAFE] parallel_layers declared but parallel-layers.sh not sourceable." >&2
    exit 1
  fi
  GROUP_ID="${SD_GROUP_ID:-PR-${N}}"
  LAYER=$(pl_layer_of "$LOCK_LAYERS" "$GROUP_ID" 2>&1) || {
    echo "[STOP-SAFE] GROUP_ID '${GROUP_ID}' not found in parallel_layers." >&2
    exit 1
  }
  if [[ "$LAYER" == "1" ]]; then
    BASE_BRANCH="$DEFAULT_BRANCH"
  else
    BASE_BRANCH="${FEATURE_PREFIX}/task-$(pl_first_in_layer "$LOCK_LAYERS" "$((LAYER - 1))")"
  fi
  TASK_BRANCH="${FEATURE_PREFIX}/task-${GROUP_ID}"
fi

git fetch origin --quiet
WORKTREE_DIR=".worktrees/${WORKTREE_NS}/task-${N}"
mkdir -p ".worktrees/${WORKTREE_NS}"
git worktree prune
git branch -D "$TASK_BRANCH" 2>/dev/null || true
rm -rf "$WORKTREE_DIR" 2>/dev/null || true
git worktree add "$WORKTREE_DIR" -b "$TASK_BRANCH" "origin/$BASE_BRANCH" 2>/dev/null \
  || git worktree add "$WORKTREE_DIR" -b "$TASK_BRANCH" "$BASE_BRANCH"

echo "WORKTREE_DIR=$WORKTREE_DIR"
echo "TASK_BRANCH=$TASK_BRANCH"
echo "BASE_BRANCH=$BASE_BRANCH"
