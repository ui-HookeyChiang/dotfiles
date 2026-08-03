#!/usr/bin/env bash
# flow-merge cleanup event wrapper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLEANUP_SCRIPT="$REPO_ROOT/_shared/stack/post-merge-cleanup.sh"

MODE="${FLOW_MERGE_CLEANUP_MODE:-${1:-}}"

case "$MODE" in
  stack)
    FEATURE_PREFIX="${FLOW_MERGE_FEATURE_PREFIX:-${2:-}}"
    TOTAL_TASKS="${FLOW_MERGE_TOTAL_TASKS:-${3:-}}"
    DEFAULT_BRANCH="${FLOW_MERGE_DEFAULT_BRANCH:-${4:-}}"
    if [[ -z "$FEATURE_PREFIX" || -z "$TOTAL_TASKS" || -z "$DEFAULT_BRANCH" ]]; then
      echo "ERROR: cleanup stack requires FLOW_MERGE_FEATURE_PREFIX, FLOW_MERGE_TOTAL_TASKS, FLOW_MERGE_DEFAULT_BRANCH" >&2
      exit 2
    fi
    bash "$CLEANUP_SCRIPT" stack "$FEATURE_PREFIX" "$TOTAL_TASKS" "$DEFAULT_BRANCH"
    ;;
  single)
    BRANCH_NAME="${FLOW_MERGE_BRANCH_NAME:-${2:-}}"
    DEFAULT_BRANCH="${FLOW_MERGE_DEFAULT_BRANCH:-${3:-}}"
    if [[ -z "$BRANCH_NAME" || -z "$DEFAULT_BRANCH" ]]; then
      echo "ERROR: cleanup single requires FLOW_MERGE_BRANCH_NAME and FLOW_MERGE_DEFAULT_BRANCH" >&2
      exit 2
    fi
    bash "$CLEANUP_SCRIPT" single "$BRANCH_NAME" "$DEFAULT_BRANCH"
    ;;
  "")
    echo "ERROR: cleanup event requires FLOW_MERGE_CLEANUP_MODE=stack|single" >&2
    exit 2
    ;;
  *)
    echo "ERROR: unknown cleanup mode: $MODE" >&2
    exit 2
    ;;
esac
