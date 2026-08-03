#!/usr/bin/env bash
# tests/home-inside-repo-guard/test.sh — install.sh refuses to run when HOME
# resolves inside the checkout. install.sh writes global agent stores under
# HOME; a repo-local HOME would scatter install artifacts through the repo.
# Run from the worktree root: bash scripts/tests/home-inside-repo-guard/test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

DRY_FLAGS=(--dry-run --skip-bins --skip-extras --skip-symlinks)

# ── Case 1: HOME == repo root → exit 2, nothing written ─────────────────────
set +e
OUT1="$(HOME="$REPO_ROOT" bash "$REPO_ROOT/install.sh" "${DRY_FLAGS[@]}" 2>&1)"
RC1=$?
set -e
if [ "$RC1" -eq 2 ]; then
  pass "case1: HOME == repo root → exit 2"
else
  fail "case1: HOME == repo root exited $RC1, expected 2"
  echo "$OUT1" | sed 's/^/    /'
fi
if echo "$OUT1" | grep -q 'HOME points inside this checkout'; then
  pass "case1: error names the offending HOME"
else
  fail "case1: no 'HOME points inside this checkout' message"
fi
# install.sh creates $HOME/.agents/skills and $HOME/.claude/skills; with HOME at
# the repo root those land directly in the checkout.
if test -d "$REPO_ROOT/.agents/skills"; then
  fail "case1: guard ran too late — .agents/skills created under repo root"
else
  pass "case1: no .agents/skills written under repo root"
fi

# ── Case 2: HOME == subdir inside repo → exit 2 ─────────────────────────────
SUB_HOME="$REPO_ROOT/.home-guard-test-$$"
TMP_HOME="$(mktemp -d)"
# The symlink itself must live OUTSIDE the checkout: a link inside the repo has
# a repo-local logical path too, so it cannot distinguish logical from physical
# resolution. Only an external link with a repo-internal target does. Keep it
# out of TMP_HOME so case 6's external-HOME run sees a pristine directory.
LINK_DIR="$(mktemp -d)"
LINK_HOME="$LINK_DIR/link-into-repo"
trap 'rm -rf "$SUB_HOME" "$TMP_HOME" "$LINK_DIR"' EXIT
mkdir -p "$SUB_HOME"
set +e
OUT2="$(HOME="$SUB_HOME" bash "$REPO_ROOT/install.sh" "${DRY_FLAGS[@]}" 2>&1)"
RC2=$?
set -e
if [ "$RC2" -eq 2 ]; then
  pass "case2: HOME inside repo subdir → exit 2"
else
  fail "case2: HOME inside repo subdir exited $RC2, expected 2"
  echo "$OUT2" | sed 's/^/    /'
fi
if test -d "$SUB_HOME/.claude/skills" || test -d "$SUB_HOME/.agents/skills"; then
  fail "case2: guard ran too late — install stores created under repo-local HOME"
else
  pass "case2: no install stores created under repo-local HOME"
fi

# ── Case 3: HOME is a symlink pointing into the checkout → exit 2 ───────────
ln -s "$SUB_HOME" "$LINK_HOME"
set +e
OUT3="$(HOME="$LINK_HOME" bash "$REPO_ROOT/install.sh" "${DRY_FLAGS[@]}" 2>&1)"
RC3=$?
set -e
if [ "$RC3" -eq 2 ]; then
  pass "case3: symlinked HOME resolving into repo → exit 2"
else
  fail "case3: symlinked HOME exited $RC3, expected 2"
  echo "$OUT3" | sed 's/^/    /'
fi

# ── Case 4: HOME unset → exit 2 ─────────────────────────────────────────────
set +e
OUT4="$(env -u HOME bash "$REPO_ROOT/install.sh" "${DRY_FLAGS[@]}" 2>&1)"
RC4=$?
set -e
if [ "$RC4" -eq 2 ]; then
  pass "case4: unset HOME → exit 2"
else
  fail "case4: unset HOME exited $RC4, expected 2"
  echo "$OUT4" | sed 's/^/    /'
fi

# ── Case 5: HOME pointing at a nonexistent directory → exit 2 ──────────────
set +e
OUT5="$(HOME="$TMP_HOME/does-not-exist" bash "$REPO_ROOT/install.sh" "${DRY_FLAGS[@]}" 2>&1)"
RC5=$?
set -e
if [ "$RC5" -eq 2 ]; then
  pass "case5: nonexistent HOME → exit 2"
else
  fail "case5: nonexistent HOME exited $RC5, expected 2"
  echo "$OUT5" | sed 's/^/    /'
fi

# ── Case 6: external HOME → guard does not fire, install proceeds ───────────
set +e
# This suite usually runs from a task worktree, where the temporary-worktree
# source guard fires; override it so only the HOME guard is under test here.
OUT6="$(HOME="$TMP_HOME" SKILL_INSTALL_ALLOW_WORKTREE=1 bash "$REPO_ROOT/install.sh" "${DRY_FLAGS[@]}" 2>&1)"
RC6=$?
set -e
if [ "$RC6" -eq 0 ]; then
  pass "case6: external temp HOME → exit 0"
else
  fail "case6: external temp HOME exited $RC6, expected 0"
  echo "$OUT6" | sed 's/^/    /'
fi
if echo "$OUT6" | grep -q 'HOME points inside this checkout'; then
  fail "case6: guard false-positived on external HOME"
else
  pass "case6: guard silent for external HOME"
fi
# Positive assertion: the run must reach the end, not exit 0 inertly.
if echo "$OUT6" | grep -q 'Summary:'; then
  pass "case6: dry-run reached the Summary line"
else
  fail "case6: no Summary line — run exited 0 without doing the install pass"
  echo "$OUT6" | sed 's/^/    /'
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
