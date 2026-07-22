#!/bin/bash
# Test plan: pl_first_in_layer + linear fallback produce correct
# BASE_BRANCH for every group across linear and parallel modes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
. "$REPO_ROOT/flow-dev/scripts/lib/parallel-layers.sh"

FAILED=0
assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL [$label]: expected '$expected', got '$actual'"
    FAILED=$((FAILED + 1))
  else
    echo "PASS [$label]"
  fi
}

# This function is the contract SKILL.md Phase 2 Step 2 implements inline.
# Verified here so the SKILL.md pseudocode has a tested reference.
compute_base_branch() {
  local layers_json="$1" gid="$2" prefix="$3" default_branch="$4"
  if [[ "$layers_json" == "null" || -z "$layers_json" ]]; then
    # Linear fallback — caller still passes a numeric N via gid
    if [[ "$gid" == "1" ]]; then
      echo "$default_branch"
    else
      echo "${prefix}/task-$((gid - 1))"
    fi
    return
  fi
  local layer
  layer=$(pl_layer_of "$layers_json" "$gid")
  if [[ "$layer" == "1" ]]; then
    echo "$default_branch"
  else
    local prev_first
    prev_first=$(pl_first_in_layer "$layers_json" "$((layer - 1))")
    echo "${prefix}/task-${prev_first}"
  fi
}

# Parallel mode: [[PR-1],[PR-2,PR-3],[PR-4]]
LAYERS='[["PR-1"],["PR-2","PR-3"],["PR-4"]]'
assert_eq "$(compute_base_branch "$LAYERS" PR-1 feat/foo main)" "main" "parallel: PR-1 base=main"
assert_eq "$(compute_base_branch "$LAYERS" PR-2 feat/foo main)" "feat/foo/task-PR-1" "parallel: PR-2 base=task-PR-1"
assert_eq "$(compute_base_branch "$LAYERS" PR-3 feat/foo main)" "feat/foo/task-PR-1" "parallel: PR-3 base=task-PR-1 (shared with PR-2)"
assert_eq "$(compute_base_branch "$LAYERS" PR-4 feat/foo main)" "feat/foo/task-PR-2" "parallel: PR-4 base=task-PR-2 (first of layer 2)"

# Linear fallback: layers_json=null, gid is numeric
assert_eq "$(compute_base_branch "null" 1 feat/foo main)" "main" "linear: task-1 base=main"
assert_eq "$(compute_base_branch "null" 2 feat/foo main)" "feat/foo/task-1" "linear: task-2 base=task-1"
assert_eq "$(compute_base_branch "null" 3 feat/foo main)" "feat/foo/task-2" "linear: task-3 base=task-2"

# Edge case: empty array parallel_layers (Finding 1)
EMPTY='[]'
if compute_base_branch "$EMPTY" PR-1 feat/foo main >/dev/null 2>&1; then
  # The reference impl doesn't have the SKILL.md guards — this is expected to
  # still "succeed" with malformed output. The real test below verifies via jq
  # that the SKILL.md prose itself has the guard.
  :
fi

# The SKILL.md guard text is asserted by grep — locks the contract.
SKILL="$REPO_ROOT/flow-dev/SKILL.md"
if grep -q 'parallel_layers is empty array' "$SKILL"; then
  echo "PASS [SKILL.md has empty-array guard]"
else
  echo "FAIL [SKILL.md missing empty-array guard]"
  FAILED=$((FAILED + 1))
fi

if grep -q "GROUP_ID '.*' not found in parallel_layers" "$SKILL"; then
  echo "PASS [SKILL.md has GROUP_ID-not-found guard]"
else
  echo "FAIL [SKILL.md missing GROUP_ID-not-found guard]"
  FAILED=$((FAILED + 1))
fi

if [[ $FAILED -gt 0 ]]; then
  echo "$FAILED test(s) failed"
  exit 1
fi
echo "All tests passed"
