# Fat Reference

This reference file has a large code block that would normally trigger G8.
The skill-audit composer must suppress the G8 belongs-in-references/ finding
on this file because it IS already a reference file.

## Commands

```bash
git fetch origin
git checkout -b feature/fat
git add -p
git commit -m "fat"
git push -u origin feature/fat
gh pr create --title "fat" --body "fat body"
gh pr view --json state
gh pr merge --squash
git fetch origin
git checkout main
git pull
git branch -d feature/fat
git push origin --delete feature/fat
git log --oneline -5
git status
git diff HEAD~1
git stash list
git stash show
```
