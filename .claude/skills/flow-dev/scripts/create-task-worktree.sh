#!/bin/bash
# create-task-worktree.sh — resolve BASE_BRANCH (linear/parallel), create worktree.
# Usage: create-task-worktree.sh <feature_prefix> <task_n> <default_branch> <worktree_ns> [ticket_path]
# Env: SD_GROUP_ID (parallel mode override for task identifier)
# Outputs (eval-able): WORKTREE_DIR=... TASK_BRANCH=... BASE_BRANCH=...
# Exit: 0=ok, 1=STOP-SAFE (lock corruption / GROUP_ID not found / blocked task)

set -euo pipefail

FEATURE_PREFIX="${1:?Usage: create-task-worktree.sh <feature_prefix> <task_n> <default_branch> <worktree_ns> [ticket_path]}"
N="${2:?missing task_n}"
DEFAULT_BRANCH="${3:?missing default_branch}"
WORKTREE_NS="${4:?missing worktree_ns}"
TICKET_PATH="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=flow-dev/scripts/lock.sh
. "$SCRIPT_DIR/lock.sh"

fd_lock_resolve_base_branch "$FEATURE_PREFIX" "$N" "$DEFAULT_BRANCH" || exit 1
BASE_BRANCH="$FD_LOCK_BASE_BRANCH"
TASK_BRANCH="$FD_LOCK_TASK_BRANCH"

TASK_ID="task-${N}"
if [[ -n "$TICKET_PATH" ]]; then
  fd_lock_register_ticket_task "$TASK_ID" "$TICKET_PATH" || exit 1
fi
git fetch origin --quiet
WORKTREE_DIR=".worktrees/${WORKTREE_NS}/task-${N}"
mkdir -p ".worktrees/${WORKTREE_NS}"
git worktree prune
git branch -D "$TASK_BRANCH" 2>/dev/null || true
rm -rf "$WORKTREE_DIR" 2>/dev/null || true

# Resolve the start point: prefer origin/$BASE_BRANCH; if absent, only proceed
# off the local ref when its SHA matches the upstream (i.e. not unpushed).
if git rev-parse --verify --quiet "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  START_POINT="origin/$BASE_BRANCH"
elif git rev-parse --verify --quiet "$BASE_BRANCH" >/dev/null 2>&1; then
  LOCAL_SHA=$(git rev-parse "$BASE_BRANCH")
  UPSTREAM_SHA=$(git ls-remote origin "refs/heads/$BASE_BRANCH" 2>/dev/null | awk '{print $1}')
  if [[ -n "$UPSTREAM_SHA" && "$LOCAL_SHA" == "$UPSTREAM_SHA" ]]; then
    START_POINT="$BASE_BRANCH"
  else
    echo "STOP-SAFE: origin/$BASE_BRANCH does not exist and local '$BASE_BRANCH' appears unpushed." >&2
    echo "Push the branch first (git push origin $BASE_BRANCH) or check parent-gate." >&2
    exit 1
  fi
else
  echo "STOP-SAFE: base branch '$BASE_BRANCH' not found locally or on origin." >&2
  exit 1
fi

git worktree add "$WORKTREE_DIR" -b "$TASK_BRANCH" "$START_POINT" >/dev/null

echo "WORKTREE_DIR=$WORKTREE_DIR"
echo "TASK_BRANCH=$TASK_BRANCH"
echo "BASE_BRANCH=$BASE_BRANCH"
