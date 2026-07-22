---
name: refs-skill
description: Test skill for auditing references coverage. Use when testing that skill-audit runs engines on all reference files in the references/ directory.
---

# refs-skill

This skill exists to test that the skill-audit composer correctly fans
out the syntax and semantic engines to every file in the references/ directory,
not just SKILL.md. It has enough prose here to qualify for G1 semantic detection.
The purpose of this fixture is to exercise the per-file loop and F-suppression
logic that prevents phantom frontmatter findings on non-SKILL targets.

## Setup steps

```bash
git fetch origin
git checkout -b feature/test
git add -p
git commit -m "initial"
git push -u origin feature/test
gh pr create --title "test" --body "test body"
gh pr view --json state
gh pr merge --squash
git fetch origin
git checkout main
git pull
git branch -d feature/test
git push origin --delete feature/test
git log --oneline -5
git status
git diff HEAD~1
git stash list
git stash show
```
