#!/usr/bin/env bash
# tests/register-claudemd/test.sh — TDD tests for --register-claudemd flag.
# Spec: docs/superpowers/specs/2026-06-23-memory-discipline-doc-design.md §--register-claudemd
# Run from worktree root: bash scripts/tests/register-claudemd/test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PASS=0
FAIL=0

# This suite usually runs from a task worktree, where install.sh's
# temporary-worktree source guard refuses to run. Only --register-claudemd is
# under test here, so opt out of that guard for every install.sh call below.
export SKILL_INSTALL_ALLOW_WORKTREE=1

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Single consolidated cleanup — per-case `trap ... EXIT` would each REPLACE the
# prior handler, leaking all but the last TMP dir. Declare all empty first so
# the trap references defined vars even if a later mktemp never runs.
TMP1="" TMP2="" TMP3="" TMP4="" TMP5="" TMP6="" TMP7="" TMP8="" TMP9=""
cleanup() { rm -rf "$TMP1" "$TMP2" "$TMP3" "$TMP4" "$TMP5" "$TMP6" "$TMP7" "$TMP8" "$TMP9"; }
trap cleanup EXIT

# ── Case 1: default-off — no register:/would register: line ─────────────────
TMP1="$(mktemp -d)"
mkdir -p "$TMP1/.claude"

OUT1="$(HOME="$TMP1" bash "$REPO_ROOT/install.sh" --dry-run --skip-bins --skip-extras 2>&1)"
if echo "$OUT1" | rg -q 'register:'; then
  fail "case1: default-off printed 'register:' without --register-claudemd"
else
  pass "case1: default-off prints no register:/would register: line"
fi

# ── Case 2: absent-include — appends include + warning; idempotent second run ─
TMP2="$(mktemp -d)"
mkdir -p "$TMP2/.claude"
printf '# x\n' > "$TMP2/.claude/CLAUDE.md"

OUT2="$(HOME="$TMP2" bash "$REPO_ROOT/install.sh" --register-claudemd --skip-bins --skip-extras 2>&1)"
if echo "$OUT2" | rg -q 'registered: CLAUDE.md @memory-discipline.md'; then
  pass "case2a: absent-include → prints registered:"
else
  fail "case2a: absent-include did not print registered:"
fi

if rg -q '^@memory-discipline\.md$' "$TMP2/.claude/CLAUDE.md" 2>/dev/null; then
  pass "case2b: CLAUDE.md contains anchored @memory-discipline.md line"
else
  fail "case2b: CLAUDE.md missing anchored @memory-discipline.md line"
fi

if rg -q 'WARNING:' "$TMP2/.claude/CLAUDE.md" 2>/dev/null; then
  pass "case2c: CLAUDE.md contains WARNING: line"
else
  fail "case2c: CLAUDE.md missing WARNING: line"
fi

if rg -q '^# x$' "$TMP2/.claude/CLAUDE.md" 2>/dev/null; then
  pass "case2d: original content preserved (append-only)"
else
  fail "case2d: original content lost (not append-only)"
fi

# Second run — idempotent
OUT2B="$(HOME="$TMP2" bash "$REPO_ROOT/install.sh" --register-claudemd --skip-bins --skip-extras 2>&1)"
if echo "$OUT2B" | rg -q '\[present\] CLAUDE.md @memory-discipline.md \(already registered\)'; then
  pass "case2e: second run prints [present] already registered"
else
  fail "case2e: second run did not print [present] already registered"
  echo "  output was:"
  echo "$OUT2B" | sed 's/^/    /'
fi

COUNT="$(rg -c '^@memory-discipline\.md$' "$TMP2/.claude/CLAUDE.md" 2>/dev/null || echo 0)"
if [ "$COUNT" -eq 1 ]; then
  pass "case2f: no duplicate @memory-discipline.md after second run"
else
  fail "case2f: @memory-discipline.md appears $COUNT times (expected 1)"
fi

# ── Case 3: no CLAUDE.md — file is created with include + warning ───────────
TMP3="$(mktemp -d)"
mkdir -p "$TMP3/.claude"
# Do NOT create CLAUDE.md

OUT3="$(HOME="$TMP3" bash "$REPO_ROOT/install.sh" --register-claudemd --skip-bins --skip-extras 2>&1)"
if echo "$OUT3" | rg -q 'registered: CLAUDE.md @memory-discipline.md'; then
  pass "case3a: no-CLAUDE.md → prints registered:"
else
  fail "case3a: no-CLAUDE.md did not print registered:"
fi

if [ -f "$TMP3/.claude/CLAUDE.md" ]; then
  pass "case3b: CLAUDE.md created when absent"
else
  fail "case3b: CLAUDE.md not created"
fi

if rg -q '^@memory-discipline\.md$' "$TMP3/.claude/CLAUDE.md" 2>/dev/null; then
  pass "case3c: created CLAUDE.md contains @memory-discipline.md"
else
  fail "case3c: created CLAUDE.md missing @memory-discipline.md"
fi

# ── Case 4: symlink guard — skip, never write through symlink ────────────────
TMP4="$(mktemp -d)"
mkdir -p "$TMP4/.claude"
TGT4="$TMP4/dotfiles-claudemd"
printf 'dotfiles content\n' > "$TGT4"
ln -s "$TGT4" "$TMP4/.claude/CLAUDE.md"
BEFORE4="$(cat "$TGT4")"

OUT4="$(HOME="$TMP4" bash "$REPO_ROOT/install.sh" --register-claudemd --skip-bins --skip-extras 2>&1)"
if echo "$OUT4" | rg -q 'is a symlink \(dotfiles-owned; not appending @-include\)'; then
  pass "case4a: symlink guard printed dotfiles-owned skip message"
else
  fail "case4a: symlink guard did not print expected message"
  echo "  output was:"
  echo "$OUT4" | sed 's/^/    /'
fi

AFTER4="$(cat "$TGT4")"
if [ "$BEFORE4" = "$AFTER4" ]; then
  pass "case4b: symlink target file byte-unchanged (nothing appended)"
else
  fail "case4b: symlink target was modified"
fi

# ── Case 5: dry-run — prints would register:, CLAUDE.md unchanged ───────────
TMP5="$(mktemp -d)"
mkdir -p "$TMP5/.claude"
printf '# existing\n' > "$TMP5/.claude/CLAUDE.md"
BEFORE5="$(cat "$TMP5/.claude/CLAUDE.md")"

OUT5="$(HOME="$TMP5" bash "$REPO_ROOT/install.sh" --register-claudemd --dry-run --skip-bins --skip-extras 2>&1)"
if echo "$OUT5" | rg -q 'would register: CLAUDE.md @memory-discipline.md'; then
  pass "case5a: dry-run prints would register:"
else
  fail "case5a: dry-run did not print would register:"
  echo "  output was:"
  echo "$OUT5" | sed 's/^/    /'
fi

AFTER5="$(cat "$TMP5/.claude/CLAUDE.md")"
if [ "$BEFORE5" = "$AFTER5" ]; then
  pass "case5b: dry-run left CLAUDE.md unchanged"
else
  fail "case5b: dry-run modified CLAUDE.md"
fi

# ── Case 6: hint fires — doc in place, no flag, no CLAUDE.md ─────────────────
TMP6="$(mktemp -d)"
mkdir -p "$TMP6/.claude"
# No CLAUDE.md created — absent file trivially lacks the include

OUT6="$(HOME="$TMP6" bash "$REPO_ROOT/install.sh" --skip-bins --skip-extras 2>&1)"
if echo "$OUT6" | rg -q 're-run with --register-claudemd'; then
  pass "case6: hint fires — prints re-run with --register-claudemd"
else
  fail "case6: hint did not fire"
  echo "  output was:"
  echo "$OUT6" | sed 's/^/    /'
fi

# ── Case 7: hint suppressed when --register-claudemd flag passed ──────────────
TMP7="$(mktemp -d)"
mkdir -p "$TMP7/.claude"

OUT7="$(HOME="$TMP7" bash "$REPO_ROOT/install.sh" --register-claudemd --skip-bins --skip-extras 2>&1)"
if echo "$OUT7" | rg -q 're-run with --register-claudemd'; then
  fail "case7: hint printed when --register-claudemd flag was passed"
else
  pass "case7: hint suppressed when --register-claudemd flag passed"
fi

# ── Case 8: hint suppressed when include already in CLAUDE.md ────────────────
TMP8="$(mktemp -d)"
mkdir -p "$TMP8/.claude"
printf '@memory-discipline.md\n' > "$TMP8/.claude/CLAUDE.md"

OUT8="$(HOME="$TMP8" bash "$REPO_ROOT/install.sh" --skip-bins --skip-extras 2>&1)"
if echo "$OUT8" | rg -q 're-run with --register-claudemd'; then
  fail "case8: hint printed when include already registered"
else
  pass "case8: hint suppressed when include already in CLAUDE.md"
fi

# ── Case 9: hint suppressed when CLAUDE.md is a symlink ──────────────────────
TMP9="$(mktemp -d)"
mkdir -p "$TMP9/.claude"
TGT9="$TMP9/dotfiles-claudemd"
printf 'dotfiles content\n' > "$TGT9"
ln -s "$TGT9" "$TMP9/.claude/CLAUDE.md"

OUT9="$(HOME="$TMP9" bash "$REPO_ROOT/install.sh" --skip-bins --skip-extras 2>&1)"
if echo "$OUT9" | rg -q 're-run with --register-claudemd'; then
  fail "case9: hint printed when CLAUDE.md is a symlink"
else
  pass "case9: hint suppressed when CLAUDE.md is a symlink"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
