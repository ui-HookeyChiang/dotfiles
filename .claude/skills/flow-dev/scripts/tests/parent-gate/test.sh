#!/usr/bin/env bash
# Tests for parent-gate enforcement in create-task-worktree.sh + update-task-status.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CREATE_SCRIPT="$REPO_ROOT/flow-dev/scripts/create-task-worktree.sh"
UPDATE_SCRIPT="$REPO_ROOT/flow-dev/scripts/update-task-status.sh"

PASSED=0
FAILED=0
pass() { ((PASSED++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); echo "  FAIL: $1" >&2; }

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

setup_repo() {
  local dir="$TMPDIR_ROOT/$1"
  mkdir -p "$dir"
  (cd "$dir" && git init -b main --quiet && git commit --allow-empty -m "init" --quiet)
  local bare="$TMPDIR_ROOT/${1}-bare"
  git clone --bare --quiet "$dir" "$bare" 2>/dev/null
  (cd "$dir" && git remote remove origin 2>/dev/null; git remote add origin "$bare"
   git fetch origin --quiet 2>/dev/null)
  echo "$dir"
}

# --- Case 1: unblocked ticket registers task with empty blocked_by ---
echo "Case 1: unblocked ticket → task registered, worktree created"
REPO=$(setup_repo case1)
mkdir -p "$REPO/docs/ticket"
cat > "$REPO/docs/ticket/task-a.md" <<'EOF'
## Blocked by

None.
EOF
out=$(cd "$REPO" && bash "$CREATE_SCRIPT" feat/foo 1 main ns-foo docs/ticket/task-a.md 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q 'WORKTREE_DIR='; then
  pass "unblocked: worktree created"
else
  fail "unblocked: rc=$rc out=$out"
fi
# Check task registered in lock.
if (cd "$REPO" && jq -e '.tasks[] | select(.id == "task-1")' .flow-dev-lock >/dev/null 2>&1); then
  pass "unblocked: task registered in lock"
else
  fail "unblocked: task not in lock"
fi
BLOCKED_BY=$(cd "$REPO" && jq -c '.tasks[] | select(.id == "task-1") | .blocked_by' .flow-dev-lock)
if [[ "$BLOCKED_BY" == "[]" ]]; then
  pass "unblocked: blocked_by is empty"
else
  fail "unblocked: blocked_by=$BLOCKED_BY"
fi

# --- Case 2: blocked ticket, blocker not completed → STOP-SAFE ---
echo "Case 2: blocked, blocker not done → STOP-SAFE"
REPO=$(setup_repo case2)
mkdir -p "$REPO/docs/ticket"
cat > "$REPO/docs/ticket/task-a.md" <<'EOF'
## Blocked by

None.
EOF
cat > "$REPO/docs/ticket/task-b.md" <<'EOF'
## Blocked by

- docs/ticket/task-a.md (must finish first)
EOF
# Create task-a first (registers it as pending).
(cd "$REPO" && bash "$CREATE_SCRIPT" feat/bar 1 main ns-bar docs/ticket/task-a.md >/dev/null 2>&1)
# Now try task-b — should fail because task-a is still pending.
out=$(cd "$REPO" && bash "$CREATE_SCRIPT" feat/bar 2 main ns-bar docs/ticket/task-b.md 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'STOP-SAFE.*blocked'; then
  pass "blocked: STOP-SAFE fires"
else
  fail "blocked: rc=$rc out=$out"
fi

# --- Case 3: blocked ticket, blocker completed → proceeds ---
echo "Case 3: blocked, blocker completed → proceeds"
REPO=$(setup_repo case3)
mkdir -p "$REPO/docs/ticket"
cat > "$REPO/docs/ticket/task-a.md" <<'EOF'
## Blocked by

None.
EOF
cat > "$REPO/docs/ticket/task-b.md" <<'EOF'
## Blocked by

- docs/ticket/task-a.md (must finish first)
EOF
# Create + complete task-a.
(cd "$REPO" && bash "$CREATE_SCRIPT" feat/baz 1 main ns-baz docs/ticket/task-a.md >/dev/null 2>&1)
(cd "$REPO" && bash "$UPDATE_SCRIPT" task-1 completed >/dev/null 2>&1)
# Push task-1 branch so task-2 can base on it.
(cd "$REPO" && git push origin feat/baz/task-1 --quiet 2>/dev/null)
# Now task-b should succeed.
out=$(cd "$REPO" && bash "$CREATE_SCRIPT" feat/baz 2 main ns-baz docs/ticket/task-b.md 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q 'WORKTREE_DIR='; then
  pass "blocker completed: worktree created"
else
  fail "blocker completed: rc=$rc out=$out"
fi

# --- Case 4: update-task-status works ---
echo "Case 4: update-task-status transitions"
REPO=$(setup_repo case4)
mkdir -p "$REPO/docs/ticket"
cat > "$REPO/docs/ticket/task-a.md" <<'EOF'
## Blocked by

None.
EOF
(cd "$REPO" && bash "$CREATE_SCRIPT" feat/qux 1 main ns-qux docs/ticket/task-a.md >/dev/null 2>&1)
STATUS=$(cd "$REPO" && jq -r '.tasks[0].status' .flow-dev-lock)
if [[ "$STATUS" == "pending" ]]; then
  pass "initial status: pending"
else
  fail "initial status: $STATUS"
fi
(cd "$REPO" && bash "$UPDATE_SCRIPT" task-1 in_progress >/dev/null 2>&1)
STATUS=$(cd "$REPO" && jq -r '.tasks[0].status' .flow-dev-lock)
if [[ "$STATUS" == "in_progress" ]]; then
  pass "updated to in_progress"
else
  fail "in_progress: $STATUS"
fi
(cd "$REPO" && bash "$UPDATE_SCRIPT" task-1 completed >/dev/null 2>&1)
STATUS=$(cd "$REPO" && jq -r '.tasks[0].status' .flow-dev-lock)
if [[ "$STATUS" == "completed" ]]; then
  pass "updated to completed"
else
  fail "completed: $STATUS"
fi

# --- Case 5: update-task-status rejects invalid status ---
echo "Case 5: invalid status → STOP-SAFE"
REPO=$(setup_repo case5)
mkdir -p "$REPO/docs/ticket"
cat > "$REPO/docs/ticket/task-a.md" <<'EOF'
## Blocked by

None.
EOF
(cd "$REPO" && bash "$CREATE_SCRIPT" feat/inv 1 main ns-inv docs/ticket/task-a.md >/dev/null 2>&1)
out=$(cd "$REPO" && bash "$UPDATE_SCRIPT" task-1 bogus 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'STOP-SAFE.*Invalid'; then
  pass "invalid status rejected"
else
  fail "invalid status: rc=$rc out=$out"
fi

# --- Case 6: update-task-status on missing task → STOP-SAFE ---
echo "Case 6: missing task → STOP-SAFE"
REPO=$(setup_repo case6)
mkdir -p "$REPO/docs/ticket"
cat > "$REPO/docs/ticket/task-a.md" <<'EOF'
## Blocked by

None.
EOF
(cd "$REPO" && bash "$CREATE_SCRIPT" feat/mis 1 main ns-mis docs/ticket/task-a.md >/dev/null 2>&1)
out=$(cd "$REPO" && bash "$UPDATE_SCRIPT" task-99 completed 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'STOP-SAFE.*not found'; then
  pass "missing task STOP-SAFE"
else
  fail "missing task: rc=$rc out=$out"
fi

# --- Case 7: backward compat — no ticket_path arg → no parent-gate ---
echo "Case 7: no ticket arg → backward compat (no gate)"
REPO=$(setup_repo case7)
out=$(cd "$REPO" && bash "$CREATE_SCRIPT" feat/compat 1 main ns-compat 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q 'WORKTREE_DIR='; then
  pass "backward compat: works without ticket"
else
  fail "backward compat: rc=$rc out=$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
