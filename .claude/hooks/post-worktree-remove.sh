#!/usr/bin/env bash
# PostToolUse hook (Bash tool): clean CRG DB when a worktree is removed.
#
# Fires on `git worktree remove` — deletes the corresponding
# ~/.cache/crg/<repo>/<branch-slug>/ DB to reclaim disk space.
# Long-lived branches (stable/*, main, master, release/*) are preserved.
#
# No-op when:
#   - Not triggered by a `git worktree remove` Bash command
#   - No matching DB found in ~/.cache/crg/
set -uo pipefail

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[[ "$tool" == "Bash" ]] || exit 0
printf '%s' "$cmd" | grep -q 'git worktree remove' || exit 0

# Resolve repo name from git-common-dir.
git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
git_common_abs="$(cd "$git_common" 2>/dev/null && pwd -P)" || exit 0
repo_name="$(basename "$(dirname "$git_common_abs")")"
crg_cache="$HOME/.cache/crg/${repo_name}"
[[ -d "$crg_cache" ]] || exit 0

# Extract worktree path from the remove command (first non-flag arg after 'remove').
worktree_path="$(printf '%s' "$cmd" \
  | sed 's/.*git worktree remove//' \
  | tr ' ' '\n' \
  | awk '/^-/{next} /^$/{next} {print; exit}')"
[[ -n "$worktree_path" ]] || exit 0

# Expand relative path.
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[[ -n "$cwd" ]] || cwd="$PWD"
case "$worktree_path" in
  /*) ;;
  *)  worktree_path="${cwd}/${worktree_path}" ;;
esac

# Derive branch name from the worktree's HEAD before it's removed.
branch="$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[[ -n "$branch" ]] || exit 0

# Preserve long-lived branches.
case "$branch" in
  stable/*|main|master|release/*) exit 0 ;;
esac

# Delete the DB slot.
db_slot="${crg_cache}/${branch//\//-}"
[[ -d "$db_slot" ]] && rm -rf "$db_slot"
exit 0
