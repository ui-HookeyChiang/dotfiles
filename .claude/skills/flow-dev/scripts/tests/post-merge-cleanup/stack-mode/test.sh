#!/usr/bin/env bash
# Tests for _shared/stack/post-merge-cleanup.sh — stack subcommand.
#
# 4 cases per Sprint 3 spec §D3b:
#   - happy: 3 task-N branches, all mock MERGED -> exit 0
#   - idempotent: run twice, second run still exit 0
#   - lock-removal: pre-create .flow-dev-lock, run cleanup -> lock gone
#   - bad-args: missing total_tasks -> exit 2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/stack/post-merge-cleanup.sh"

PASSED=0
FAILED=0
FAIL_NAMES=()

pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
fail() { FAILED=$((FAILED+1)); FAIL_NAMES+=("$1"); echo "  FAIL: $1 — $2"; }

# Build a tmp git repo with N stacked task branches (real branches, real refs).
make_repo() {
  local tmp="$1" feature_prefix="$2" total="$3"
  local origin="$tmp/origin.git" work="$tmp/work"
  git init --bare -q "$origin"
  git clone -q "$origin" "$work" 2>/dev/null
  git -C "$work" config user.email t@t
  git -C "$work" config user.name t
  git -C "$work" checkout -q -b main
  echo init > "$work/README.md"
  git -C "$work" add README.md
  git -C "$work" -c commit.gpgsign=false commit -q -m initial
  git -C "$work" push -q origin main
  for n in $(seq 1 "$total"); do
    local base
    if [[ "$n" -eq 1 ]]; then base="main"; else base="${feature_prefix}/task-$((n-1))"; fi
    git -C "$work" checkout -q -b "${feature_prefix}/task-${n}" "$base"
    echo "task-${n}" > "$work/task-${n}.txt"
    git -C "$work" add "task-${n}.txt"
    git -C "$work" -c commit.gpgsign=false commit -q -m "feat: task ${n}"
    git -C "$work" push -q origin "${feature_prefix}/task-${n}"
  done
  git -C "$work" checkout -q main
  echo "$work"
}

# ---------------------------------------------------------------------------
# Case: bad-args — missing total_tasks -> exit 2
# ---------------------------------------------------------------------------
test_bad_args() {
  local out rc
  out=$(bash "$SCRIPT" stack feat/foo 2>&1) && rc=0 || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q 'Usage:'; then
    pass "case bad-args missing total_tasks -> exit 2 + Usage"
  else
    fail "bad-args" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: happy — 3 task branches, SD_SKIP_REMOTE=1 -> exit 0 + OK line
# ---------------------------------------------------------------------------
test_happy() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  local work; work=$(make_repo "$tmp" feat/foo 3)
  local out rc
  out=$( cd "$work" && SD_SKIP_REMOTE=1 \
         bash "$SCRIPT" stack feat/foo 3 main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q 'OK: post-merge-cleanup stack done'; then
    pass "case happy 3 tasks -> exit 0 + OK line"
  else
    fail "happy" "rc=$rc, out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Case: idempotent — run twice, second invocation still exit 0
# (best-effort branch -D / push --delete tolerate "already gone" via || true)
# ---------------------------------------------------------------------------
test_idempotent() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  local work; work=$(make_repo "$tmp" feat/foo 2)
  local rc1 rc2 out2
  ( cd "$work" && SD_SKIP_REMOTE=1 \
    bash "$SCRIPT" stack feat/foo 2 main >/dev/null 2>&1 ) && rc1=0 || rc1=$?
  out2=$( cd "$work" && SD_SKIP_REMOTE=1 \
          bash "$SCRIPT" stack feat/foo 2 main 2>&1 ) && rc2=0 || rc2=$?
  if [[ "$rc1" == 0 && "$rc2" == 0 ]] && echo "$out2" | grep -q 'OK: post-merge-cleanup stack done'; then
    pass "case idempotent -> second run exit 0 (branches already gone, no error)"
  else
    fail "idempotent" "rc1=$rc1, rc2=$rc2, out2=$out2"
  fi
}

# ---------------------------------------------------------------------------
# Case: lock-removal — pre-create .flow-dev-lock, run cleanup -> lock gone
# ---------------------------------------------------------------------------
test_lock_removal() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  local work; work=$(make_repo "$tmp" feat/foo 1)
  # Place lock at the worktree root (the path cleanup_all_locks resolves).
  # Use valid v1 JSON (no parallel_layers) so the I2 unparseable-lock guard
  # in post-merge-cleanup.sh does not fire — this case exercises the
  # cleanup_all_locks path, not the JSON-parse-error path (which has its
  # own dedicated assertion in tests/post-merge-cleanup-layer-order/test.sh).
  cat > "$work/.flow-dev-lock" <<'EOF'
{"version":1,"spec_path":"docs/specs/active/stale.md","feature_branch":"feat/foo/task-1","created_at":"2026-05-29T00:00:00Z","skill_version":"flow-dev@test"}
EOF
  [[ -f "$work/.flow-dev-lock" ]] || { fail "lock-removal" "pre-condition: lock not created"; return; }
  local out rc
  out=$( cd "$work" && SD_SKIP_REMOTE=1 \
         bash "$SCRIPT" stack feat/foo 1 main 2>&1 ) && rc=0 || rc=$?
  if [[ "$rc" == 0 ]] && [[ ! -f "$work/.flow-dev-lock" ]]; then
    pass "case lock-removal -> lock file gone after cleanup"
  else
    fail "lock-removal" "rc=$rc, lock_still_present=$([[ -f "$work/.flow-dev-lock" ]] && echo yes || echo no), out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
echo "================================================"
echo " test post-merge-cleanup.sh — stack subcommand"
echo "================================================"
test_bad_args
test_happy
test_idempotent
test_lock_removal
echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [[ "$FAILED" -gt 0 ]]; then
  echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
