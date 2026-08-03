#!/usr/bin/env bash
# tests/worktree-source-guard/test.sh — install.sh refuses to install FROM a
# disposable task worktree. Every store install.sh writes is a symlink whose
# target is the checkout it was run from; installing from .worktrees/<task>
# leaves ~/.claude/agents and ~/.agents/skills pointing at a tree that is
# deleted when the task ends, and a later re-run from the main checkout only
# WARNs and skips (mismatched symlinks need --force), so the breakage persists.
# Run from the worktree root: bash scripts/tests/worktree-source-guard/test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

DRY_FLAGS=(--dry-run --skip-bins --skip-extras --skip-symlinks)
TMP_HOME="$(mktemp -d)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$STAGE"' EXIT

# A real git worktree is unnecessary: the guard's job is to reject a source path
# living under a .worktrees/ (or .worktree/) segment. Copy the installer and the
# libs it sources into such a path.
run_from() {
  local dir="$1"
  mkdir -p "$dir/scripts/lib"
  cp "$REPO_ROOT/install.sh" "$dir/install.sh"
  cp -r "$REPO_ROOT/scripts/lib/." "$dir/scripts/lib/"
  set +e
  OUT="$(HOME="$TMP_HOME" bash "$dir/install.sh" "${DRY_FLAGS[@]}" 2>&1)"
  RC=$?
  set -e
}

# ── Case 1: source under .worktrees/<task> → exit 2 ─────────────────────────
run_from "$STAGE/repo/.worktrees/agent-parity-opencode-20260727"
if [ "$RC" -eq 2 ]; then
  pass "case1: install from .worktrees/<task> → exit 2"
else
  fail "case1: install from .worktrees/<task> exited $RC, expected 2"
  echo "$OUT" | sed 's/^/    /'
fi
if echo "$OUT" | grep -q 'temporary worktree'; then
  pass "case1: error names the temporary-worktree cause"
else
  fail "case1: no 'temporary worktree' message"
  echo "$OUT" | sed 's/^/    /'
fi

# ── Case 2: singular .worktree/ segment is rejected too ─────────────────────
run_from "$STAGE/repo2/.worktree/some-task"
if [ "$RC" -eq 2 ]; then
  pass "case2: install from .worktree/<task> → exit 2"
else
  fail "case2: install from .worktree/<task> exited $RC, expected 2"
  echo "$OUT" | sed 's/^/    /'
fi

# ── Case 3: nested .claude/worktrees/ segment is rejected ───────────────────
run_from "$STAGE/repo3/.claude/worktrees/some-task"
if [ "$RC" -eq 2 ]; then
  pass "case3: install from .claude/worktrees/<task> → exit 2"
else
  fail "case3: install from .claude/worktrees/<task> exited $RC, expected 2"
  echo "$OUT" | sed 's/^/    /'
fi

# ── Case 4: override escape hatch lets a worktree run proceed ───────────────
mkdir -p "$STAGE/repo4/.worktrees/task"
cp "$REPO_ROOT/install.sh" "$STAGE/repo4/.worktrees/task/install.sh"
mkdir -p "$STAGE/repo4/.worktrees/task/scripts/lib"
cp -r "$REPO_ROOT/scripts/lib/." "$STAGE/repo4/.worktrees/task/scripts/lib/"
set +e
OUT4="$(HOME="$TMP_HOME" SKILL_INSTALL_ALLOW_WORKTREE=1 \
  bash "$STAGE/repo4/.worktrees/task/install.sh" "${DRY_FLAGS[@]}" 2>&1)"
RC4=$?
set -e
if [ "$RC4" -eq 0 ]; then
  pass "case4: SKILL_INSTALL_ALLOW_WORKTREE=1 → exit 0"
else
  fail "case4: override exited $RC4, expected 0"
  echo "$OUT4" | sed 's/^/    /'
fi

# ── Case 5: ordinary checkout path → guard silent, install proceeds ─────────
# Staged under a plain path, NOT $REPO_ROOT: this suite itself normally runs
# from a task worktree, where the guard is supposed to fire.
run_from "$STAGE/plain-checkout"
OUT5="$OUT"
RC5="$RC"
if [ "$RC5" -eq 0 ]; then
  pass "case5: ordinary checkout → exit 0"
else
  fail "case5: ordinary checkout exited $RC5, expected 0"
  echo "$OUT5" | sed 's/^/    /'
fi
if echo "$OUT5" | grep -q 'temporary worktree'; then
  fail "case5: guard false-positived on ordinary checkout"
else
  pass "case5: guard silent for ordinary checkout"
fi
if echo "$OUT5" | grep -q 'Summary:'; then
  pass "case5: dry-run reached the Summary line"
else
  fail "case5: no Summary line — run exited 0 without doing the install pass"
  echo "$OUT5" | sed 's/^/    /'
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
