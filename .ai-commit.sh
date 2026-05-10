#!/bin/bash
set -euo pipefail

hash=${1:-}

# Get AI-generated commit message
commit_message=$(~/.ai-commit-msg.sh "$hash")

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
