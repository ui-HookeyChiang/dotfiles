#!/usr/bin/env bash
# voter-lock.sh — acquire / release atomic mkdir-based lock per voter slot.
# Used by both voter sub-agents (for ballot.json publish) and main agent
# (for synthetic TIMEOUT_FAIL writes).
#
# Usage:
#   voter-lock.sh acquire <private-dir>   # exits 0 on win, 1 on lost
#   voter-lock.sh release <private-dir>   # always exits 0
set -euo pipefail
cmd="${1:?usage: voter-lock.sh <acquire|release> <private-dir>}"
private_dir="${2:?missing private-dir}"
mkdir -p "$private_dir"
lock="$private_dir/.lock-acquired"

case "$cmd" in
  acquire)
    if mkdir "$lock" 2>/dev/null; then exit 0; else exit 1; fi
    ;;
  release)
    rmdir "$lock" 2>/dev/null || true
    exit 0
    ;;
  *)
    echo "unknown cmd: $cmd" >&2; exit 2
    ;;
esac
