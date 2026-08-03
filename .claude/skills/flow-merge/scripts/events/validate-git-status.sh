#!/usr/bin/env bash
# Validate a merge target checkout before flow-merge mutates it.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: validate-git-status.sh [--repo <path>] [--require-merged <base-ref> <candidate-ref> [label]]

Checks:
  - repo is a git worktree
  - tracked and untracked status is clean
  - optional candidate ref is already merged into base ref
EOF
}

REPO="${FLOW_MERGE_REPO:-.}"
REQUIRE_BASE=""
REQUIRE_CANDIDATE=""
REQUIRE_LABEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"; shift 2 ;;
    --require-merged)
      REQUIRE_BASE="${2:-}"
      REQUIRE_CANDIDATE="${3:-}"
      REQUIRE_LABEL="${4:-$REQUIRE_CANDIDATE}"
      shift 3
      if [[ $# -gt 0 && "$1" != --* ]]; then
        shift
      fi
      ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "ERROR: repo path is empty" >&2
  exit 2
fi
if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git worktree: $REPO" >&2
  exit 1
fi

status="$(git -C "$REPO" status --porcelain)"
if [[ -n "$status" ]]; then
  echo "ERROR: git status is not clean in $REPO" >&2
  printf '%s\n' "$status" >&2
  exit 1
fi

if [[ -n "$REQUIRE_BASE" || -n "$REQUIRE_CANDIDATE" ]]; then
  if [[ -z "$REQUIRE_BASE" || -z "$REQUIRE_CANDIDATE" ]]; then
    echo "ERROR: --require-merged needs <base-ref> and <candidate-ref>" >&2
    exit 2
  fi
  git -C "$REPO" rev-parse --verify "$REQUIRE_BASE^{commit}" >/dev/null
  git -C "$REPO" rev-parse --verify "$REQUIRE_CANDIDATE^{commit}" >/dev/null
  if ! git -C "$REPO" merge-base --is-ancestor "$REQUIRE_CANDIDATE" "$REQUIRE_BASE"; then
    echo "ERROR: $REQUIRE_LABEL is not merged into $REQUIRE_BASE" >&2
    exit 1
  fi
fi

echo "OK: git status clean"
