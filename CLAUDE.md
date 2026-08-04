# dotfiles · Project Rules

Personal dotfiles — the canonical source for global agent config and skills.

## Layout

- `.claude/CLAUDE.md` — GLOBAL instructions (symlinked to `~/.claude/CLAUDE.md` by the installer). Edit here, never in `~/.claude/` directly.
- `.claude/docs/agents/` — docs `@imported` by the global CLAUDE.md.
- `.claude/skills/` — canonical live skill source; the installer fans these out to `~/.claude/skills` and `~/.config/opencode/skills`. Skill-authoring rules: `.claude/skills/CLAUDE.md`.
- `.opencode/skill/` — parity bridge so OpenCode sees the same project skills.

## Development

- Never push directly to the default branch — all changes go through PRs.
- Develop in a linked worktree (`git worktree add .worktrees/<branch> -b <branch> origin/master`).
- After changing skills or config, run `bash .claude/skills/agent-parity/scripts/check-parity.sh --scope project` — done when 0 gap(s).

## Issue tracker

Local markdown under `docs/ticket/` as `YYYY-MM-DD-<slug>.md` with a `Status:` line.
