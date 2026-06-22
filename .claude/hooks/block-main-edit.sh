#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): worktree-enforce (mode "X").
#
# Rule: edits are forbidden in the MAIN working tree. Develop in a linked
# worktree instead, so the main checkout always reflects a clean merged state
# and concurrent work cannot clobber it.
#
# Detection: resolve the edit target's git directory and compare
#   git -C <dir> rev-parse --git-dir   vs   --git-common-dir
#   - main checkout: the two are EQUAL (both `.git`, or both the common dir),
#     and the git-dir path does NOT contain `/worktrees/`  -> DENY.
#   - linked worktree: the git-dir is `<common>/worktrees/<name>`, which differs
#     from the common dir and contains `/worktrees/`        -> ALLOW.
#   - not a git repo: ALLOW (fail open).
#
# Escape hatch: ALLOW_MAIN_EDIT=1 bypasses the check (allow). Kept for the
# legitimate cases: editing this hook / settings.json itself, an initial commit
# before any worktree exists, or a deliberate urgent single-operator edit.
set -uo pipefail

# --- Escape hatch -----------------------------------------------------------
if [ "${ALLOW_MAIN_EDIT:-}" = "1" ]; then
  exit 0
fi

# --- Parse hook input -------------------------------------------------------
# NotebookEdit carries notebook_path instead of file_path; fall back to either,
# then to PWD when the tool gives no path at all.
input="$(cat)"
file_path="$(printf '%s' "$input" \
  | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"

if [ -n "$file_path" ]; then
  dir="$(dirname "$file_path")"
else
  dir="${PWD}"
fi
# Resolve a relative file_path against PWD so `git -C` lands in the right repo.
case "$dir" in
  /*) ;;
  *)  dir="${PWD}/${dir}" ;;
esac

deny() {  # $1 = reason
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# --- Resolve the target's git directory -------------------------------------
# Use the absolute git-dir so the `/worktrees/` test is independent of CWD. A
# linked worktree's git-dir is `<common>/worktrees/<name>`; the main checkout's
# git-dir is the common dir itself and never contains that segment.
gitdir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" || exit 0  # not a repo -> allow
[ -n "$gitdir" ] || exit 0

case "$gitdir" in
  */worktrees/*) ;;                      # linked worktree -> allow
  *)
    deny "Blocked: editing the main working tree is forbidden.

  target: $dir

Create a linked worktree and develop there instead:

  git worktree add .worktree/<branch> -b <branch>
  cd .worktree/<branch>

Escape hatch for a deliberate single-operator edit: ALLOW_MAIN_EDIT=1."
    ;;
esac

# Reached only for a linked worktree: allow.
exit 0
