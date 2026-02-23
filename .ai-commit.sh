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
      echo "Warning: cherry-pick conflict on $c, skipping" >&2
      git cherry-pick --skip
    fi
  done
fi

# Pop the stashed changes
if [ "$stashed" = 1 ]; then
  git stash pop
fi
