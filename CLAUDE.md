# dotfiles · Project Rules

Personal dotfiles. Agent config and skills live in the private `skill-dev`
submodule; this repo carries the installer and non-agent dotfiles.

## Layout

- `skill-dev/` — private submodule (github.com/ui-HookeyChiang/skill-dev): canonical source for skills, hooks, scripts, `_shared/`, and `.claude/` (user-global config: CLAUDE.md, settings.json, statusline-command.sh, docs/agents/).
- The installer delegates agent-harness work to `skill-dev/install.sh` (skills fanout, agent definitions, hooks, config-doc symlinks, locked extras, OpenCode/Cursor config). Only `_shared` sibling symlinks remain in `dotfiles/install.sh`.

## Development

- Never push directly to the default branch — all changes go through PRs.
- Develop in a linked worktree (`git worktree add .worktrees/<branch> -b <branch> origin/master`).
- After changing skills or config, run `bash skill-dev/agent-compat/scripts/check-compat.sh --scope project` — done when 0 gap(s).

## Issue tracker

Local markdown under `docs/ticket/` as `YYYY-MM-DD-<slug>.md` with a `Status:` line.
