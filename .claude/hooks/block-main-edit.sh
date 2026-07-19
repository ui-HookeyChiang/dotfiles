#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): branch-enforce (mode "X").
#
# Rule: edits are forbidden on the default branch. Develop on a feature branch.
#
# Detection: compare current branch vs origin/HEAD (fallback: main).
#   - current branch == default branch -> DENY.
#   - current branch != default branch -> ALLOW.
#   - not a git repo: ALLOW (fail open).
#
# Escape hatch: ALLOW_MAIN_EDIT=1 bypasses the check (allow). Kept for the
# legitimate cases: editing this hook / settings.json itself, an initial commit
# before any branch exists, or a deliberate urgent single-operator edit.
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

# --- Resolve the target's default and current branch -----------------------
default_branch="$(git -C "$dir" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|^origin/||')"
# Fallback if origin/HEAD isn't set
[ -z "$default_branch" ] && default_branch="main"

current_branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[ -z "$current_branch" ] && exit 0

if [ "$current_branch" = "$default_branch" ]; then
  deny "Blocked: editing on the default branch ($default_branch) is forbidden.

  target: $dir

Switch to a feature branch first:

  git checkout -b <branch>

Or create a linked worktree:

  git worktree add .worktree/<branch> -b <branch>

Escape hatch for a deliberate single-operator edit: ALLOW_MAIN_EDIT=1."
fi

exit 0
