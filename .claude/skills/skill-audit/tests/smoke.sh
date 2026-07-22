#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$HERE/../skill-audit}"   # audit a known real skill
out="$(bash "$HERE/scripts/run.sh" "$TARGET" 2>&1)"; rc=$?
# Must run all three deterministic legs — anchor to run.sh's own `## ` headers
# so a stray "deadcode: not found" stderr line cannot satisfy the grep.
echo "$out" | grep -q '^## deadcode' || { echo "FAIL: no deadcode section"; exit 1; }
echo "$out" | grep -q '^## syntax'   || { echo "FAIL: no syntax-metrics section"; exit 1; }
echo "$out" | grep -q '^## semantic' || { echo "FAIL: no semantic-prefilter section"; exit 1; }
# Pure script (no agent): clean exit is 0 (problem) or 2 (clean); rc=1 is an
# engine error and must FAIL — a crashing run.sh must not pass.
[ "$rc" != 1 ] || { echo "FAIL: run.sh errored (rc=1)"; exit 1; }
echo "PASS"
