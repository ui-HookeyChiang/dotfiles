#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/stack/post-merge-cleanup.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"
git init -q -b main .
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"

# Test 1: parallel-mode lock → iteration order matches parallel_layers
cat > .flow-dev-lock <<'EOF'
{
  "version": 2,
  "spec_path": "docs/specs/active/foo.md",
  "feature_branch": "feat/foo/task-PR-1",
  "created_at": "2026-05-29T00:00:00Z",
  "skill_version": "flow-dev@test",
  "parallel_layers": [["PR-1"], ["PR-2", "PR-3"], ["PR-4"]]
}
EOF

OUT=$(SD_POST_MERGE_DRY_ORDER=1 \
  bash "$SCRIPT" stack feat/foo 4 main 2>&1 || true)

EXPECTED_ORDER="PR-1 PR-2 PR-3 PR-4"
ACTUAL_ORDER=$(echo "$OUT" | grep '^cleanup order:' | sed 's/cleanup order: //')
if [[ "$ACTUAL_ORDER" != "$EXPECTED_ORDER" ]]; then
  echo "FAIL: expected order '$EXPECTED_ORDER', got '$ACTUAL_ORDER'" >&2
  exit 1
fi
echo "PASS [parallel: cleanup order matches parallel_layers]"

# Test 2: TOTAL_TASKS mismatch against TASK_ORDER length must STOP-SAFE
OUT=$(SD_POST_MERGE_DRY_ORDER=1 \
  bash "$SCRIPT" stack feat/foo 3 main 2>&1 || true)
if ! echo "$OUT" | grep -q "TASK_ORDER length mismatch"; then
  echo "FAIL: expected TASK_ORDER mismatch STOP-SAFE on TOTAL_TASKS=3 vs 4-group layers" >&2
  exit 1
fi
echo "PASS [TASK_ORDER length-mismatch guard fires]"

# Test 3: linear-mode lock (v1, no parallel_layers) → 1..N order
cat > .flow-dev-lock <<'EOF'
{
  "version": 1,
  "spec_path": "docs/specs/active/foo.md",
  "feature_branch": "feat/foo/task-1",
  "created_at": "2026-05-29T00:00:00Z",
  "skill_version": "flow-dev@test"
}
EOF
OUT=$(SD_POST_MERGE_DRY_ORDER=1 \
  bash "$SCRIPT" stack feat/foo 3 main 2>&1 || true)
EXPECTED_ORDER="1 2 3"
ACTUAL_ORDER=$(echo "$OUT" | grep '^cleanup order:' | sed 's/cleanup order: //')
if [[ "$ACTUAL_ORDER" != "$EXPECTED_ORDER" ]]; then
  echo "FAIL: linear fallback expected '$EXPECTED_ORDER', got '$ACTUAL_ORDER'" >&2
  exit 1
fi
echo "PASS [linear: cleanup order is 1..N]"

# Test 4: no lock file at all → linear fallback (same as Test 3)
rm .flow-dev-lock
OUT=$(SD_POST_MERGE_DRY_ORDER=1 \
  bash "$SCRIPT" stack feat/foo 2 main 2>&1 || true)
EXPECTED_ORDER="1 2"
ACTUAL_ORDER=$(echo "$OUT" | grep '^cleanup order:' | sed 's/cleanup order: //')
if [[ "$ACTUAL_ORDER" != "$EXPECTED_ORDER" ]]; then
  echo "FAIL: no-lock expected '$EXPECTED_ORDER', got '$ACTUAL_ORDER'" >&2
  exit 1
fi
echo "PASS [no lock: linear fallback]"

# Test 5 (I2): malformed lock JSON must STOP-SAFE (not silently linear)
echo "{not valid json" > .flow-dev-lock
set +e
OUT=$(SD_POST_MERGE_DRY_ORDER=1 \
  bash "$SCRIPT" stack feat/foo 3 main 2>&1)
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  echo "FAIL: malformed lock should have refused" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "unparseable"; then
  echo "FAIL: expected unparseable STOP-SAFE, got: $OUT" >&2
  exit 1
fi
echo "PASS [I2: malformed lock refused]"

echo "All tests passed"
