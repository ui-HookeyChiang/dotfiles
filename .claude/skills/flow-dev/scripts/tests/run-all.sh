#!/bin/bash
# tests/run-all.sh — discover and run every per-script test.sh under this
# directory. Each test.sh is responsible for its own assertion output and
# exits 0 on success / non-zero on failure.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0
TOTAL=0

# Stable iteration order.
# Discover both:
#   - per-suite test.sh files (one per subdirectory, original convention)
#   - top-level test_*.sh forwarders / standalone integration tests
#     (e.g. integration/test_ssot_e2e.sh from the SSOT feature)
mapfile -t TESTS < <(find "$HERE" -type f \( -name test.sh -o -name 'test_*.sh' \) | sort)

for t in "${TESTS[@]}"; do
  TOTAL=$((TOTAL + 1))
  echo
  echo "==== $t ===="
  if bash "$t"; then
    :
  else
    FAILED=$((FAILED + 1))
  fi
done

echo
echo "tests/run-all: $TOTAL suite(s), $FAILED failed."
if (( FAILED == 0 )); then exit 0; else exit 1; fi
