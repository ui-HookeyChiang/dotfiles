---
name: sync-to-dotfiles
argument-hint: "[--apply]"
description: One-way sync skill-dev hooks, generic skills, and docs/agents into the personal dotfiles repo, excluding ubiquiti-* skills. User-only; run when you want the dotfiles .claude copy refreshed from a skill-dev checkout before committing dotfiles.
disable-model-invocation: true
---

# Sync to dotfiles

Copy `skill-dev`'s `hooks/`, generic skills, and `docs/agents/` into the
personal dotfiles repo at `~/dotfiles/.claude/`. Excludes `ubiquiti-*` skills
(work-specific — must not enter personal dotfiles).

**Dotfiles-repo tool.** Lives in this repo at
`~/dotfiles/.claude/skills/sync-to-dotfiles/`. Not installed by skill-dev's
`install.sh` and never synced by itself — it is the sync's destination side.

## Run

Dry-run first (default — writes nothing, prints the plan):

```
bash ~/dotfiles/.claude/skills/sync-to-dotfiles/scripts/sync-to-dotfiles.sh
```

Apply:

```
bash ~/dotfiles/.claude/skills/sync-to-dotfiles/scripts/sync-to-dotfiles.sh --apply
```

## Source must be clean

The script reads `SRC` (default `~/.claude/skill-dev`) as-is. That checkout may
sit on a feature branch with uncommitted edits — syncing it would copy WIP.
Point `SRC` at a clean tree on `origin/main` first:

```
git -C ~/.claude/skill-dev worktree add /tmp/sync-src origin/main
SRC=/tmp/sync-src bash ~/dotfiles/.claude/skills/sync-to-dotfiles/scripts/sync-to-dotfiles.sh --apply
git -C ~/.claude/skill-dev worktree remove /tmp/sync-src --force
```

## After

The script leaves dotfiles **uncommitted** — it never commits or pushes.
Review and commit yourself:

```
cd ~/dotfiles && git status
```

`~/.claude/skills/` live skills come from `skill-dev` symlinks; the dotfiles
skills copy is an offline backup only, not the live source.

## Overrides

- `SRC=<path>` — skill-dev checkout to read from (default `~/.claude/skill-dev`).
- `DST=<path>` — dotfiles `.claude` dir to write to (default `~/dotfiles/.claude`).
