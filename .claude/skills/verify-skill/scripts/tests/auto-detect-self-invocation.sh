#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_SKILL_ROOT="$(realpath "$HERE/..")"
set +e
out="$("$HERE/auto-detect-mode.sh" "$VERIFY_SKILL_ROOT" 2>&1)"
rc=$?
set -e
test "$rc" = "3" || { echo "expected exit 3, got $rc"; exit 1; }
echo "$out" | grep -qi 'self-invocation'
echo "PASS: auto-detect-self-invocation"
