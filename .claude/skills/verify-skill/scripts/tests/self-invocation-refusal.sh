#!/usr/bin/env bash
# SC9 — verify-skill cannot grade itself. End-to-end at auto-detect-mode.sh
# level (the gate that all main-agent entrypoints flow through).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
VS_ROOT="$(realpath "$HERE/..")"

# Direct path
set +e
out=$("$HERE/auto-detect-mode.sh" "$VS_ROOT" 2>&1)
rc=$?
set -e
test "$rc" = "3" || { echo "FAIL: expected exit 3 got $rc"; exit 1; }
echo "$out" | grep -qi 'self-invocation' || { echo "FAIL: missing self-invocation marker"; exit 1; }

# Symlink to self (e.g. ~/.claude/skills/verify-skill resolves to repo path)
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
ln -s "$VS_ROOT" "$TMP/vs-link"
set +e
"$HERE/auto-detect-mode.sh" "$TMP/vs-link" 2>/dev/null
rc=$?
set -e
test "$rc" = "3" || { echo "FAIL via symlink: got $rc"; exit 1; }
echo "PASS: self-invocation-refusal (SC9)"
