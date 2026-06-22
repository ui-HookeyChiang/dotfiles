#!/usr/bin/env bash
# tests/test-claude-hooks.sh — TAP-13 suite for the worktree-enforce hook.
#
# Covers .claude/hooks/block-main-edit.sh (PreToolUse, mode "X"):
#   - an edit target in a MAIN working tree is denied and nudged to a worktree
#   - an edit target in a LINKED worktree is allowed
#   - ALLOW_MAIN_EDIT=1 bypasses the check on a main-checkout target
#   - a target outside any git repo fails open (allow)
#   - a relative file_path is resolved against PWD before the repo lookup
#
# The deny decision compares `git rev-parse --git-dir` against
# `--git-common-dir`: in a main checkout they are equal, in a linked worktree
# the git-dir lives under <common>/worktrees/<name>.
#
# Output: TAP-13. Exit 0 on all pass, non-zero otherwise.

# NOT -e: this suite self-manages failures via counters, and many checks
# legitimately use the non-zero return of a command (is_deny, grep -q) as data.
# CI invokes scripts as `bash -e {0}`, so explicitly disable errexit here.
set +e
set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
BLOCK="$repo_root/.claude/hooks/block-main-edit.sh"

echo "TAP version 13"
N=0; FAILS=0
pass(){ N=$((N+1)); echo "ok $N - $1"; }
fail(){ N=$((N+1)); FAILS=$((FAILS+1)); echo "not ok $N - $1"; }
chk(){ if [ "$1" = pass ]; then pass "$2"; else fail "$2"; fi; }

command -v jq >/dev/null 2>&1 || { echo "1..0 # SKIP jq not installed"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "1..0 # SKIP git not installed"; exit 0; }

# Allow output is empty (hook exits 0 silently); deny output is JSON. Guard the
# empty case explicitly — jq's exit code on empty stdin differs across versions
# (1.6 vs 1.7), so never let jq adjudicate "no input". For real JSON, use
# `// empty` + a value test that is exit-code-stable across jq versions.
is_deny(){
  [ -n "$1" ] || return 1   # empty == allow
  [ "$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = deny ]
}
inp(){ jq -nc --arg f "$1" '{session_id:"s",transcript_path:"/dev/null",tool_input:{file_path:$f}}'; }
run_block(){ "$BLOCK" <<<"$(inp "$1")"; }  # echoes hook stdout; $1 = file_path

# Fixtures: a real main checkout plus a linked worktree.
MAIN="$(mktemp -d)"
WT="${MAIN}-wt"
NONGIT="$(mktemp -d)"
trap 'git -C "$MAIN" worktree remove --force "$WT" 2>/dev/null; rm -rf "$MAIN" "$WT" "$NONGIT" 2>/dev/null' EXIT
git -C "$MAIN" init -q
git -C "$MAIN" config user.email t@t; git -C "$MAIN" config user.name t
echo x > "$MAIN/f"; git -C "$MAIN" add f; git -C "$MAIN" commit -qm init
git -C "$MAIN" worktree add -q "$WT" -b wtbranch
echo x > "$WT/g"

# 1: edit target in the main checkout is denied
out="$(run_block "$MAIN/f")"
is_deny "$out" && chk pass "main-checkout target denied" \
               || chk fail "main-checkout target denied"

# 2: edit target in a linked worktree is allowed (empty output)
out="$(run_block "$WT/g")"
is_deny "$out" && chk fail "linked-worktree target allowed" \
               || chk pass "linked-worktree target allowed"

# 3: deny message nudges to a worktree
out="$(run_block "$MAIN/f")"
printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' \
  | grep -q 'git worktree add' && chk pass "deny message nudges to a worktree" \
                               || chk fail "deny message nudges to a worktree"

# 4: ALLOW_MAIN_EDIT=1 bypasses the check on a main-checkout target
out="$(ALLOW_MAIN_EDIT=1 "$BLOCK" <<<"$(inp "$MAIN/f")")"
is_deny "$out" && chk fail "ALLOW_MAIN_EDIT bypasses on main checkout" \
               || chk pass "ALLOW_MAIN_EDIT bypasses on main checkout"

# 5: target outside any git repo fails open (allow)
out="$(run_block "$NONGIT/x")"
is_deny "$out" && chk fail "non-git path allowed (fail open)" \
               || chk pass "non-git path allowed (fail open)"

# 6: relative file_path resolved against PWD lands in the main checkout -> deny
out="$(cd "$MAIN" && "$BLOCK" <<<"$(inp "f")")"
is_deny "$out" && chk pass "relative path resolved against PWD denies in main" \
               || chk fail "relative path resolved against PWD denies in main"

# 7: relative file_path resolved against PWD lands in a linked worktree -> allow
out="$(cd "$WT" && "$BLOCK" <<<"$(inp "g")")"
is_deny "$out" && chk fail "relative path resolved against PWD allows in worktree" \
               || chk pass "relative path resolved against PWD allows in worktree"

# 8: NotebookEdit notebook_path field resolves (main checkout -> deny)
out="$("$BLOCK" <<<"$(jq -nc --arg f "$MAIN/nb.ipynb" \
  '{session_id:"s",tool_input:{notebook_path:$f}}')")"
is_deny "$out" && chk pass "NotebookEdit notebook_path resolves (deny in main)" \
               || chk fail "NotebookEdit notebook_path resolves (deny in main)"

# 9: no file_path falls back to PWD (run inside main checkout -> deny)
out="$(cd "$MAIN" && "$BLOCK" <<<"$(jq -nc '{session_id:"s",tool_input:{}}')")"
is_deny "$out" && chk pass "no file_path falls back to PWD (deny in main)" \
               || chk fail "no file_path falls back to PWD (deny in main)"

echo "1..$N"
[ "$FAILS" -eq 0 ]
