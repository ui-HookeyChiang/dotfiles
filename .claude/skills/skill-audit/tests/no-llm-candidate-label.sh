#!/usr/bin/env bash
# skill-semantic-audit/tests/no-llm-candidate-label.sh
# TDD test: open-concept axes under --no-llm must emit needs_probabilistic_confirm: true
# in the findings block (STDOUT), not stderr-only NOT_APPLICABLE.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# Use the g1-fixtures testdata: skill-a with --cross pointing at the fixtures dir.
# This is the real regression anchor for G1 (see testdata/g1-fixtures/expected.yaml).
FIX="$HERE/testdata/g1-fixtures/skill-a-debfactory.md"
CROSS_DIR="$HERE/testdata/g1-fixtures"

[ -f "$FIX" ] || { echo "SKIP: no g1 fixture at $FIX"; exit 0; }

ERR="$(mktemp)"
# Capture STDOUT and STDERR separately so we can assert the confirm-candidate
# lands on STDOUT (the findings block), not stderr noise.
out="$(python3 "$HERE/scripts/semantic_audit.py" "$FIX" --no-llm --cross "$CROSS_DIR" 2>"$ERR")"
rc=$?

echo "$out" | grep -q "needs_probabilistic_confirm" \
  || { echo "FAIL: open-concept axis not labelled as confirm-candidate on STDOUT"; echo "--- stdout ---"; echo "$out"; echo "--- stderr ---"; cat "$ERR"; rm -f "$ERR"; exit 1; }

# stderr still carries the NOT_APPLICABLE notice for caller visibility.
grep -q "NOT_APPLICABLE" "$ERR" \
  || { echo "FAIL: NOT_APPLICABLE notice missing from stderr"; cat "$ERR"; rm -f "$ERR"; exit 1; }

# Exit code reflects REAL findings only (open-concept candidates are advisory,
# never findings). This fixture is na-only (G1 NOT_APPLICABLE, no real findings)
# so EXIT_CLEAN(2) is expected — candidates must NOT flip exit to FLAGGED(0).
[ "$rc" = 2 ] \
  || { echo "FAIL: expected exit 2 (EXIT_CLEAN, na-only fixture), got $rc"; rm -f "$ERR"; exit 1; }

rm -f "$ERR"
echo "PASS"
