#!/usr/bin/env bash
# auto-removed.sh — after all-loop, spec-advisory.sh must reject --mode=auto.
# Pre-removal this test FAILS (auto is still accepted); post-removal it PASSES.
set -uo pipefail
cd "$(dirname "$0")"
ADVISORY="../../spec-advisory.sh"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
echo "# spec" > "$TMP/s.md"
PASS=0; FAIL=0

# Case A: --mode=auto is rejected (exit 2, invalid-mode message)
set +e
out="$(bash "$ADVISORY" --mode=auto "$TMP/s.md" 2>&1)"; rc=$?
set -e
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi 'invalid --mode value'; then
  echo "PASS auto-rejected"; PASS=$((PASS+1))
else
  echo "FAIL auto-rejected: rc=$rc out='$out'"; FAIL=$((FAIL+1))
fi

# Case B: no live mode=auto residue in the script itself (grep the source)
if grep -q 'mode=auto\|MODE.*==.*auto\|full|auto|full-loop' "$ADVISORY"; then
  echo "FAIL auto-residue-in-script"; FAIL=$((FAIL+1))
else
  echo "PASS no-auto-residue"; PASS=$((PASS+1))
fi

echo "---"; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
