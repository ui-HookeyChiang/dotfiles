#!/usr/bin/env bash
# tests/config-symlink/test.sh — TDD test for install.sh PHASE 2.6 (config-symlink)
# 5 cases from spec §Test plan.
# Run from the worktree root: bash scripts/tests/config-symlink/test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PASS=0
FAIL=0

# This suite usually runs from a task worktree, where install.sh's
# temporary-worktree source guard refuses to run. Only the config-symlink phase
# is under test here, so opt out of that guard for every install.sh call below.
export SKILL_INSTALL_ALLOW_WORKTREE=1

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ── Case 1: bash -n install.sh exits 0 ──────────────────────────────────────
bash -n "$REPO_ROOT/install.sh" 2>/dev/null \
  && pass "case1: bash -n install.sh exits 0" \
  || fail "case1: bash -n install.sh syntax error"

# ── Case 2: doc paths present ───────────────────────────────────────────────
if grep -q 'docs/ticket/' "$REPO_ROOT/docs/agents/memory-discipline.md" 2>/dev/null \
   && grep -q 'docs/adr/'   "$REPO_ROOT/docs/agents/memory-discipline.md" 2>/dev/null; then
  pass "case2: docs/agents/memory-discipline.md has docs/ticket/ and docs/adr/"
else
  fail "case2: docs/agents/memory-discipline.md missing docs/ticket/ or docs/adr/"
fi

# ── Set up a fresh tmp HOME for cases 3-5 ───────────────────────────────────
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.claude"

# ── Case 3: absent — dry-run prints would link config: ───────────────────────
OUT3="$(HOME="$TMP_HOME" bash "$REPO_ROOT/install.sh" --dry-run --skip-bins --skip-extras 2>&1)"
if echo "$OUT3" | grep -q 'would link config:' \
   && echo "$OUT3" | grep -q 'memory-discipline.md'; then
  pass "case3: absent path → would link config: ...memory-discipline.md"
else
  fail "case3: absent path did not print 'would link config: ...memory-discipline.md'"
  echo "  output was:"
  echo "$OUT3" | sed 's/^/    /'
fi

# ── Case 4: present symlink — prints [present] skip line, no would-link ──────
ln -s /dev/null "$TMP_HOME/.claude/memory-discipline.md"
OUT4="$(HOME="$TMP_HOME" bash "$REPO_ROOT/install.sh" --dry-run --skip-bins --skip-extras 2>&1)"
if echo "$OUT4" | grep -q '\[present\]' \
   && echo "$OUT4" | grep -q '(skip config; will not delete)'; then
  pass "case4: foreign symlink present → [present] ...  (skip config; will not delete)"
else
  fail "case4: foreign symlink present did not print skip line"
  echo "  output was:"
  echo "$OUT4" | sed 's/^/    /'
fi
if echo "$OUT4" | grep -q 'would link config:.*memory-discipline.md'; then
  fail "case4: printed 'would link config:' for foreign memory-discipline symlink"
else
  pass "case4: no 'would link config:' for foreign memory-discipline symlink"
fi

# ── Case 5: present real file — same skip line; file stays regular ───────────
rm "$TMP_HOME/.claude/memory-discipline.md"
: > "$TMP_HOME/.claude/memory-discipline.md"
OUT5="$(HOME="$TMP_HOME" bash "$REPO_ROOT/install.sh" --dry-run --skip-bins --skip-extras 2>&1)"
if echo "$OUT5" | grep -q '\[present\]' \
   && echo "$OUT5" | grep -q '(skip config; will not delete)'; then
  pass "case5: real file present → [present] ...  (skip config; will not delete)"
else
  fail "case5: real file present did not print skip line"
  echo "  output was:"
  echo "$OUT5" | sed 's/^/    /'
fi
if test -f "$TMP_HOME/.claude/memory-discipline.md" \
   && ! test -L "$TMP_HOME/.claude/memory-discipline.md"; then
  pass "case5: real file untouched (still regular file, not symlink)"
else
  fail "case5: real file was modified or replaced"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
