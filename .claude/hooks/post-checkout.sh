#!/usr/bin/env bash
# PostToolUse hook (Bash tool): seed CRG graph DB into a fresh worktree.
#
# When Claude Code creates a git worktree, this hook copies the main
# checkout's .code-review-graph/ SQLite DB into the new worktree so the
# first `crg update` is incremental rather than a full rebuild.
#
# No-op when:
#   - Not in a linked worktree (main checkout)
#   - code-review-graph not installed
#   - Main checkout has no .code-review-graph/ yet
#   - .code-review-graph/ already exists in the worktree (already seeded)
set -uo pipefail

# Only act on git worktree add / checkout commands.
input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

# Only fire on Bash tool calls that look like `git worktree add`.
[[ "$tool" == "Bash" ]] || exit 0
printf '%s' "$cmd" | grep -q 'git worktree add' || exit 0

# Resolve paths.
git_dir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0

# Resolve absolute paths for comparison.
git_dir_abs="$(cd "$git_dir" 2>/dev/null && pwd -P)" || exit 0
git_common_abs="$(cd "$git_common" 2>/dev/null && pwd -P)" || exit 0

# Not a linked worktree — nothing to seed.
[[ "$git_dir_abs" != "$git_common_abs" ]] || exit 0

# code-review-graph must be installed.
command -v code-review-graph >/dev/null 2>&1 || exit 0

# Find main checkout root: walk up from git-common-dir's parent.
# git-common-dir for a linked worktree resolves to <main-repo>/.git
main_git_parent="$(dirname "$git_common_abs")"
main_db="${main_git_parent}/.code-review-graph"

# No DB in main checkout yet — nothing to seed.
[[ -d "$main_db" ]] || exit 0

# Extract worktree path from the git worktree add command.
# Pattern: git worktree add [opts] <path> [<commit-ish>]
# We grab the first non-flag positional after 'add'.
worktree_path="$(printf '%s' "$cmd" \
  | sed 's/.*git worktree add//' \
  | tr ' ' '\n' \
  | grep -v '^-' \
  | grep -v '^\s*$' \
  | head -1)"
[[ -n "$worktree_path" ]] || exit 0

# Expand relative path from cwd.
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[[ -n "$cwd" ]] || cwd="$PWD"
case "$worktree_path" in
  /*) ;;
  *)  worktree_path="${cwd}/${worktree_path}" ;;
esac

# Worktree doesn't exist yet (just created by git) — wait briefly.
[[ -d "$worktree_path" ]] || exit 0

dest_db="${worktree_path}/.code-review-graph"

# Already seeded — skip.
[[ -d "$dest_db" ]] && exit 0

# Copy main DB into worktree, then run incremental update.
cp -r "$main_db" "$dest_db" 2>/dev/null || exit 0
code-review-graph update --repo "$worktree_path" --base master 2>/dev/null || true
exit 0
