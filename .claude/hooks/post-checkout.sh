#!/usr/bin/env bash
# PostToolUse hook (Bash tool): seed CRG graph DB into a fresh worktree.
#
# When Claude Code creates a git worktree, this hook seeds the CRG graph DB
# by copying the base branch's DB from ~/.cache/crg/<repo>/<base>/ then
# running an incremental update so the first review is fast.
#
# DB layout: ~/.cache/crg/<repo-name>/<branch-name>/
# Each branch gets its own persistent DB; copy base → update is faster than
# a full rebuild, and the correct base DB is used (not always "main").
#
# No-op when:
#   - Not triggered by a `git worktree add` Bash command
#   - code-review-graph not installed
#   - Base branch has no cached DB yet
#   - DB already exists for the new worktree (already seeded)
set -uo pipefail

# Only act on Bash tool calls that look like `git worktree add`.
input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[[ "$tool" == "Bash" ]] || exit 0
printf '%s' "$cmd" | grep -q 'git worktree add' || exit 0

# code-review-graph must be installed.
command -v code-review-graph >/dev/null 2>&1 || exit 0

# Resolve git-common-dir to find repo name.
git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
git_common_abs="$(cd "$git_common" 2>/dev/null && pwd -P)" || exit 0
repo_root="$(dirname "$git_common_abs")"
repo_name="$(basename "$repo_root")"

# Extract worktree path and branch/commit-ish from the git worktree add command.
# Pattern: git worktree add [opts] <path> [<commit-ish>]
# Strip flags (-b <name>, --detach, etc.) to get positional args.
positionals="$(printf '%s' "$cmd" \
  | sed 's/.*git worktree add//' \
  | tr ' ' '\n' \
  | awk '
    skip { skip=0; next }
    /^-b$|^--track$/ { skip=1; next }
    /^-/ { next }
    /^$/ { next }
    { print }
  ')"

worktree_path="$(printf '%s' "$positionals" | head -1)"
commit_ish="$(printf '%s' "$positionals" | sed -n '2p')"
[[ -n "$worktree_path" ]] || exit 0

# Expand relative worktree path from cwd.
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[[ -n "$cwd" ]] || cwd="$PWD"
case "$worktree_path" in
  /*) ;;
  *)  worktree_path="${cwd}/${worktree_path}" ;;
esac

[[ -d "$worktree_path" ]] || exit 0

# Derive base branch name from commit-ish (strip leading "origin/").
# Fallback: detect repo default branch via origin/HEAD.
if [[ -n "$commit_ish" ]]; then
  base_branch="${commit_ish#origin/}"
else
  base_branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|refs/remotes/origin/||')" || base_branch="main"
fi

# DB paths.
crg_cache="$HOME/.cache/crg/${repo_name}"
base_db="${crg_cache}/${base_branch}"

# New worktree's branch name (from -b flag or derived from worktree path).
new_branch="$(printf '%s' "$cmd" \
  | tr ' ' '\n' \
  | awk '/^-b$/{getline; print; exit}')"
[[ -n "$new_branch" ]] || new_branch="$(basename "$worktree_path")"
new_db="${crg_cache}/${new_branch}"

# Already seeded — skip.
[[ -d "$new_db" ]] && exit 0

# Base DB must exist to copy from.
[[ -d "$base_db" ]] || exit 0

# Copy base DB into new branch's cache slot, then incremental update.
mkdir -p "$crg_cache"
cp -r "$base_db" "$new_db" 2>/dev/null || exit 0
code-review-graph update \
  --repo "$worktree_path" \
  --data-dir "$new_db" \
  --base "$base_branch" 2>/dev/null || true
exit 0
