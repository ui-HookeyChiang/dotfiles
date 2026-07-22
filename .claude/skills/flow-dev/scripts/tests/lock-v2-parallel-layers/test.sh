#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WRITE_LOCK="$REPO_ROOT/flow-dev/scripts/write-lock.sh"
PREFLIGHT="$REPO_ROOT/flow-dev/scripts/phase-0-preflight.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"
git init -q -b main main
cd main
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
mkdir -p docs/specs/active
touch docs/specs/active/foo.md
git -c user.email=t@t -c user.name=t add docs && git -c user.email=t@t -c user.name=t commit -q -m "spec"
cd ..
git -C main worktree add ../wt1 -b feat/foo/task-PR-1 main

# Test 1: parallel mode — SD_PARALLEL_LAYERS set, lock has the field, version=2
cd wt1
LAYERS='[["PR-1"],["PR-2","PR-3"]]'
SD_PARALLEL_LAYERS="$LAYERS" \
  bash "$WRITE_LOCK" \
    "docs/specs/active/foo.md" \
    "feat/foo/task-PR-1" \
    "feat/foo/task-PR-1" \
    >/dev/null

if [[ ! -f .flow-dev-lock ]]; then
  echo "FAIL: lock file not created" >&2
  exit 1
fi
VERSION=$(jq -r '.version' .flow-dev-lock)
LOCK_LAYERS=$(jq -c '.parallel_layers' .flow-dev-lock)
if [[ "$VERSION" != "2" || "$LOCK_LAYERS" != "$LAYERS" ]]; then
  echo "FAIL: expected version=2 + layers=$LAYERS, got version=$VERSION + layers=$LOCK_LAYERS" >&2
  exit 1
fi
echo "PASS [parallel mode persists v2 lock]"

# Test 2: linear mode — SD_PARALLEL_LAYERS unset, lock has parallel_layers=null
rm .flow-dev-lock
bash "$WRITE_LOCK" \
  "docs/specs/active/foo.md" \
  "feat/foo/task-PR-1" \
  "feat/foo/task-PR-1" \
  >/dev/null
LOCK_LAYERS=$(jq -c '.parallel_layers' .flow-dev-lock)
if [[ "$LOCK_LAYERS" != "null" ]]; then
  echo "FAIL: linear mode should write parallel_layers=null, got $LOCK_LAYERS" >&2
  exit 1
fi
echo "PASS [linear mode writes parallel_layers=null]"

# Test 3: Phase 0 accepts v2 lock (Amendment A2)
OUT=$(bash "$PREFLIGHT" "" "$(pwd)" 2>&1 || true)
if echo "$OUT" | grep -q "Unknown.*schema version"; then
  echo "FAIL: phase-0-preflight rejected v2 lock: $OUT" >&2
  exit 1
fi
echo "PASS [phase-0-preflight accepts v2 lock]"

# Test 4: Phase 0 still accepts v1 lock for backward compat
cat > .flow-dev-lock <<'EOF'
{"version":1,"spec_path":"docs/specs/active/foo.md","feature_branch":"feat/foo/task-PR-1","created_at":"2026-05-29T00:00:00Z","skill_version":"flow-dev@test"}
EOF
OUT=$(bash "$PREFLIGHT" "" "$(pwd)" 2>&1 || true)
if echo "$OUT" | grep -q "Unknown.*schema version"; then
  echo "FAIL: phase-0-preflight rejected v1 lock (backward compat broken): $OUT" >&2
  exit 1
fi
echo "PASS [phase-0-preflight still accepts v1 lock]"

echo "All tests passed"
