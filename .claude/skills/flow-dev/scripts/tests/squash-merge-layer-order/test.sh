#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/stack/squash-merge.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"
git init -q -b main .
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"

# Test 1: parallel mode — TASK_ORDER honors layer sequence, PARENT
# resolves via pl_first_in_layer for group with layer > 1.
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

OUT=$(SD_SQUASH_MERGE_DRY_RUN=1 \
  bash "$SCRIPT" stack feat/foo 4 main 2>&1 || true)

EXPECTED_ORDER="PR-1 PR-2 PR-3 PR-4"
ACTUAL_ORDER=$(echo "$OUT" | grep '^merge order:' | sed 's/merge order: //')
if [[ "$ACTUAL_ORDER" != "$EXPECTED_ORDER" ]]; then
  echo "FAIL: expected merge order '$EXPECTED_ORDER', got '$ACTUAL_ORDER'" >&2
  exit 1
fi
echo "PASS [parallel: TASK_ORDER honors layer sequence]"

EXPECTED_PARENTS="PR-1:main PR-2:feat/foo/task-PR-1 PR-3:feat/foo/task-PR-1 PR-4:feat/foo/task-PR-2"
ACTUAL_PARENTS=$(echo "$OUT" | grep '^parent map:' | sed 's/parent map: //')
if [[ "$ACTUAL_PARENTS" != "$EXPECTED_PARENTS" ]]; then
  echo "FAIL: expected parent map '$EXPECTED_PARENTS', got '$ACTUAL_PARENTS'" >&2
  exit 1
fi
echo "PASS [parallel: PARENT via pl_first_in_layer]"

# Test 2: linear-mode fallback — no parallel_layers in lock
cat > .flow-dev-lock <<'EOF'
{
  "version": 1,
  "spec_path": "docs/specs/active/foo.md",
  "feature_branch": "feat/foo/task-1",
  "created_at": "2026-05-29T00:00:00Z",
  "skill_version": "flow-dev@test"
}
EOF
OUT=$(SD_SQUASH_MERGE_DRY_RUN=1 \
  bash "$SCRIPT" stack feat/foo 3 main 2>&1 || true)
EXPECTED_ORDER="1 2 3"
ACTUAL_ORDER=$(echo "$OUT" | grep '^merge order:' | sed 's/merge order: //')
if [[ "$ACTUAL_ORDER" != "$EXPECTED_ORDER" ]]; then
  echo "FAIL: linear fallback expected '$EXPECTED_ORDER', got '$ACTUAL_ORDER'" >&2
  exit 1
fi
echo "PASS [linear: TASK_ORDER is 1..N]"

EXPECTED_PARENTS="1:main 2:feat/foo/task-1 3:feat/foo/task-2"
ACTUAL_PARENTS=$(echo "$OUT" | grep '^parent map:' | sed 's/parent map: //')
if [[ "$ACTUAL_PARENTS" != "$EXPECTED_PARENTS" ]]; then
  echo "FAIL: linear parent map expected '$EXPECTED_PARENTS', got '$ACTUAL_PARENTS'" >&2
  exit 1
fi
echo "PASS [linear: PARENT via arithmetic]"

# Test 5 (I1): empty parallel_layers must STOP-SAFE
cat > .flow-dev-lock <<'EOF'
{
  "version": 2,
  "spec_path": "docs/specs/active/foo.md",
  "feature_branch": "feat/foo/task-PR-1",
  "created_at": "2026-05-29T00:00:00Z",
  "skill_version": "flow-dev@test",
  "parallel_layers": []
}
EOF
set +e
OUT=$(SD_SQUASH_MERGE_DRY_RUN=1 \
  bash "$SCRIPT" stack feat/foo 4 main 2>&1)
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  echo "FAIL: empty parallel_layers should have refused" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "empty TASK_ORDER"; then
  echo "FAIL: expected empty TASK_ORDER STOP-SAFE, got: $OUT" >&2
  exit 1
fi
echo "PASS [I1: empty parallel_layers refused]"

# Test 6 (I2): malformed lock JSON must STOP-SAFE (not silently linear)
echo "{not valid json" > .flow-dev-lock
set +e
OUT=$(SD_SQUASH_MERGE_DRY_RUN=1 \
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

# Test 7 (I3): TOTAL_TASKS mismatch must STOP-SAFE
cat > .flow-dev-lock <<'EOF'
{
  "version": 2,
  "spec_path": "docs/specs/active/foo.md",
  "feature_branch": "feat/foo/task-PR-1",
  "created_at": "2026-05-29T00:00:00Z",
  "skill_version": "flow-dev@test",
  "parallel_layers": [["PR-1"], ["PR-2"]]
}
EOF
set +e
OUT=$(SD_SQUASH_MERGE_DRY_RUN=1 \
  bash "$SCRIPT" stack feat/foo 5 main 2>&1)
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  echo "FAIL: TOTAL_TASKS mismatch should have refused" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "TOTAL_TASKS=5 but parallel_layers has 2"; then
  echo "FAIL: expected mismatch STOP-SAFE, got: $OUT" >&2
  exit 1
fi
echo "PASS [I3: TOTAL_TASKS mismatch refused]"

echo "All tests passed"
