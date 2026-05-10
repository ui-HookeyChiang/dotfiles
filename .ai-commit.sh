#!/bin/bash
set -euo pipefail

hash=${1:-}

# Get AI-generated commit message
commit_message=$(~/.ai-commit-msg.sh "$hash")

# F5 fallback: if .ai-commit-msg.sh bailed (e.g. missing API key), fall back
# to standard editor-driven commit. Only works for the "current commit" path —
# historic reword (hash supplied) has no graceful fallback.
if [[ -z "$commit_message" ]]; then
  echo "note: AI commit message not available — opening editor for manual commit." >&2
  if [ -z "$hash" ]; then
    exec git commit -v "$@"
  fi
  echo "Error: cannot reword historic commit $hash without AI message; aborting." >&2
  exit 1
fi

# Commit staged changes
if [ -z "$hash" ]; then
  git commit -m "$commit_message"
  exit 0
fi

# Reword historic commits
parent=$(git rev-parse "$hash"^)
tree=$(git rev-parse "$hash"^{tree})
branch=$(git branch --show-current)
commits=$(git rev-list --reverse "$hash".."$branch")
newhash=$(git commit-tree -p "$parent" -m "$commit_message" "$tree")

# Stash unstaged changes before rewriting history
if ! git diff --quiet; then
  git stash
  stashed=1
else
  stashed=0
fi

# Move branch to $newhash
git reset --hard "$newhash"
if [ -n "$commits" ]; then
  for c in $commits; do
    if ! git cherry-pick "$c"; then
      echo "ERROR: cherry-pick conflict on $c during AI-rewrite" >&2
      echo "  The commit chain has been partially rewritten. To recover:" >&2
      echo "    1. Resolve conflicts in the affected files" >&2
      echo "    2. git add <resolved-files>" >&2
      echo "    3. git cherry-pick --continue" >&2
      echo "    4. Manually replay any remaining commits: $commits" >&2
      echo "  Or to fully abort and restore the original branch:" >&2
      echo "    git cherry-pick --abort && git reset --hard $branch@{1}" >&2
      git cherry-pick --abort
      if [ "$stashed" = 1 ]; then
        git stash pop || true
      fi
      exit 1
    fi
  done
fi

# Pop the stashed changes
if [ "$stashed" = 1 ]; then
  git stash pop
fi
