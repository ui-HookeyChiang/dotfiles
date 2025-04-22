#!/bin/bash

hash=$1

# Get AI-generated commit message
commit_message=$(~/.ai-commit-msg.sh $hash)

# Commit staged changes
if [ -z $hash ];then
  git commit -m "$commit_message"
  exit 0
fi

# Reword historic commits
parent=`git rev-parse $hash^`
tree=`git rev-parse $hash^{tree}`
branch=`git branch --show-current`
commits=$(git rev-list --reverse $hash..$branch)
newhash=`git commit-tree -p $parent -m "$commit_message" $tree`

# Keep the unstaged changes
if ! git diff --quiet; then
  git stash
  stashed=1
else
  stashed=0
fi

# Move branch to $newhash
git reset --hard $newhash
if [ ! -z "$commits" ]; then
  for c in $commits; do
      git cherry-pick $c || git cherry-pick --skip
  done
fi

# Pop the changes
if [ $stashed == 1 ]; then
  git stash pop
fi
