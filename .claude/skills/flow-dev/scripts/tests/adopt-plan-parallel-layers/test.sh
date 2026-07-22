#!/bin/bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/adopt-superpowers-plan.sh"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures"
FAILED=0

assert_jq() {
  local fixture="$1" jq_expr="$2" expected="$3" label="$4"
  local actual
  actual=$(bash "$SCRIPT" "$FIXTURES/$fixture" | jq -c "$jq_expr")
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL [$label]: expected $expected, got $actual"
    FAILED=$((FAILED + 1))
  else
    echo "PASS [$label]"
  fi
}

assert_jq single-group.md '.schema_version' '2' 'schema_version v2'
assert_jq single-group.md '.parallel_layers' '[["PR-1"]]' 'single-group layers'
assert_jq all-disjoint.md '.parallel_layers' '[["PR-1","PR-2","PR-3"]]' 'all-disjoint layers'
assert_jq mild-overlap.md '.parallel_layers' '[["PR-1","PR-2","PR-3"]]' 'mild-overlap (single layer)'
assert_jq two-layer.md '.parallel_layers' '[["PR-1","PR-2"],["PR-3"]]' 'two-layer (PR-3 depends on PR-1)'
assert_jq all-shared.md '.parallel_layers' '[["PR-1"]]' 'all-shared collapses to one group'

if [[ $FAILED -gt 0 ]]; then
  echo "$FAILED test(s) failed"
  exit 1
fi
echo "All tests passed"
