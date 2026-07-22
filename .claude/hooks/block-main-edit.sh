#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit|apply_patch): worktree-enforce.
#
# Rule: writes into the MAIN checkout are forbidden. Develop in a linked git
# worktree (its own directory + branch). The main working tree is read-only.
#
# Detection (path-based, not branch-based):
#   - Resolve the target's git toplevel.
#   - Main checkout  <=> `git-dir` == `git-common-dir` (both point at .git).
#   - Linked worktree <=> `git-dir` lives under `<common>/worktrees/*`.
#   - target in a linked worktree -> ALLOW.
#   - target in the main checkout  -> DENY (unless release-whitelisted).
#   - not a git repo / cannot resolve -> ALLOW (fail open; e.g. initial commit).
#
# Release whitelist (encodes the CLAUDE.md semver-release exception): a write
# whose target path is confined to `debian/changelog` or `releases/**` is
# allowed even in the main checkout. Anything else in the same operation is
# still denied — release-adjacent code changes must go through a PR first.
#
# Escape hatch: ALLOW_MAIN_EDIT=1 bypasses the check (allow). Kept for editing
# this hook / settings.json itself, or a deliberate urgent single-operator edit.
set -uo pipefail

# --- Escape hatch -----------------------------------------------------------
if [ "${ALLOW_MAIN_EDIT:-}" = "1" ]; then
  exit 0
fi

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

DENY_MSG_TAIL="Develop in a linked worktree (its own dir + branch):

  git worktree add .worktrees/<branch> -b <branch> origin/main

or, as a subagent, call EnterWorktree.

The main checkout is read-only. Escape hatch for a deliberate
single-operator edit: ALLOW_MAIN_EDIT=1."

# Is DIR inside the MAIN checkout (not a linked worktree)?
#   main checkout : git-dir == git-common-dir
#   linked wt     : git-dir == <common>/worktrees/<name>
# Returns 0 = main checkout, 1 = linked worktree OR not a git repo (fail open).
is_main_checkout() {
  local dir="$1" gitdir commondir
  gitdir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  commondir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -z "$gitdir" ] && return 1
  [ -z "$commondir" ] && return 1
  [ "$gitdir" = "$commondir" ]
}

# Is REL (a path relative to the checkout root) within the release whitelist?
is_release_path() {
  local rel="$1"
  rel="${rel#./}"
  case "$rel" in
    debian/changelog|releases|releases/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Parse hook input -------------------------------------------------------
input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"

# apply_patch: patch text lives in tool_input.patch (Claude Code) or
# tool_input.command (Codex CLI). apply_patch runs at repo root -> use PWD.
if [ "$tool_name" = "apply_patch" ]; then
  patch="$(printf '%s' "$input" | jq -r '.tool_input.patch // .tool_input.command // empty' 2>/dev/null)"
  [ -z "$patch" ] && exit 0

  is_main_checkout "$PWD" || exit 0

  # Every touched path must be release-whitelisted to pass; else deny.
  mapfile -t files < <(printf '%s' "$patch" | grep -E '^\+\+\+ b/' | sed 's|^+++ b/||')
  [ "${#files[@]}" -eq 0 ] && exit 0
  for f in "${files[@]}"; do
    is_release_path "$f" && continue
    deny "Blocked: apply_patch writes into the main checkout.

  target: $f

$DENY_MSG_TAIL"
  done
  exit 0
fi

# NotebookEdit carries notebook_path instead of file_path; fall back to either,
# then to PWD when the tool gives no path at all.
file_path="$(printf '%s' "$input" \
  | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"

if [ -n "$file_path" ]; then
  case "$file_path" in
    /*) ;;
    *)  file_path="${PWD}/${file_path}" ;;
  esac
  dir="$(dirname "$file_path")"
else
  dir="${PWD}"
fi

# The target's dir may not exist yet (new file in a new subdir). Walk up to the
# nearest existing ancestor so git-dir resolution reflects the real checkout and
# a new-file write cannot slip past via fail-open.
while [ -n "$dir" ] && [ "$dir" != "/" ] && [ ! -d "$dir" ]; do
  dir="$(dirname "$dir")"
done

is_main_checkout "$dir" || exit 0

# Release whitelist: compute the target path relative to the checkout root.
if [ -n "$file_path" ]; then
  toplevel="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$toplevel" ]; then
    rel="${file_path#"$toplevel"/}"
    is_release_path "$rel" && exit 0
  fi
fi

deny "Blocked: writing into the main checkout is forbidden.

  target: ${file_path:-$dir}

$DENY_MSG_TAIL"
