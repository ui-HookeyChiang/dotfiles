#!/usr/bin/env bash
# Tests for block-main-edit.sh: main-checkout writes are denied, linked-worktree
# writes and the release whitelist are allowed.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-main-edit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# Build a repo with a linked worktree.
MAIN="$TMP/main"
git init -q -b main "$MAIN"
( cd "$MAIN"
  git config user.email t@t; git config user.name t
  echo x > f.txt; git add .; git commit -qm init
  git worktree add -q "$TMP/wt" -b feat >/dev/null 2>&1 )
WT="$TMP/wt"

# run <expect: allow|deny> <desc> <hook-input-json> [cwd]
run() {
  local expect="$1" desc="$2" json="$3" cwd="${4:-$MAIN}"
  local out; out="$(cd "$cwd" && printf '%s' "$json" | bash "$HOOK" 2>/dev/null)"
  local got="allow"
  printf '%s' "$out" | grep -q '"permissionDecision": "deny"' && got="deny"
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1)); printf 'ok   %s\n' "$desc"
  else
    fail=$((fail+1)); printf 'FAIL %s (expected %s, got %s)\n' "$desc" "$expect" "$got"
  fi
}

j() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }

run deny  "main checkout Write denied"          "$(j "$MAIN/f.txt")"
run allow "linked worktree Write allowed"       "$(j "$WT/f.txt")"
run allow "release: debian/changelog allowed"   "$(j "$MAIN/debian/changelog")"
run allow "release: releases/ file allowed"     "$(j "$MAIN/releases/v1.0.md")"
run deny  "main checkout non-release denied"        "$(j "$MAIN/src/code.py")"
run deny  "main checkout NEW subdir/file denied"    "$(j "$MAIN/brand/new/deep/x.py")"

# escape hatch needs env at hook time:
out="$(cd "$MAIN" && ALLOW_MAIN_EDIT=1 printf '%s' "$(j "$MAIN/f.txt")" | ALLOW_MAIN_EDIT=1 bash "$HOOK")"
printf '%s' "$out" | grep -q deny && { echo "FAIL escape hatch"; fail=$((fail+1)); } || { echo "ok   escape hatch (env)"; pass=$((pass+1)); }

# apply_patch on main checkout, non-release path -> deny
run deny "apply_patch main non-release denied" \
  '{"tool_name":"apply_patch","tool_input":{"patch":"--- a/x\n+++ b/src/x.py\n"}}'
run allow "apply_patch release path allowed" \
  '{"tool_name":"apply_patch","tool_input":{"patch":"--- a/x\n+++ b/releases/v2.md\n"}}'
run allow "apply_patch in linked worktree allowed" \
  '{"tool_name":"apply_patch","tool_input":{"patch":"--- a/x\n+++ b/src/x.py\n"}}' "$WT"

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
