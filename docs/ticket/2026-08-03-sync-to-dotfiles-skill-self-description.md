# sync-to-dotfiles SKILL.md self-description drift

Status: wontfix
Labels: bug
Created: 2026-08-03
Resolved: 2026-08-04 — sync-to-dotfiles dropped entirely; dotfiles is now the canonical skill source (no skill-dev sync), so the skill no longer exists.

## Problem

`.claude/skills/sync-to-dotfiles/SKILL.md` claims the skill "Lives in
`~/.claude/skills/`, not in any repo. Not version-controlled, not installed
by install.sh, not synced anywhere." All three claims are false:
`~/.claude/skills/sync-to-dotfiles` does not exist (the documented run
commands fail with "No such file or directory"), and the skill IS
version-controlled — in this dotfiles repo.

## Repro

```bash
bash ~/.claude/skills/sync-to-dotfiles/scripts/sync-to-dotfiles.sh
# bash: .../sync-to-dotfiles.sh: No such file or directory
```

## Fix

Update SKILL.md to state the actual home (`~/dotfiles/.claude/skills/
sync-to-dotfiles/`) and correct the run commands to the dotfiles path.

## Test plan

- Run commands in SKILL.md copy-paste clean (dry-run executes)
- No remaining `~/.claude/skills/sync-to-dotfiles` references
