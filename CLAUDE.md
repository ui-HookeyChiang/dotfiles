# dotfiles · Project Rules

Personal dotfiles. Agent config and skills live in the private `skill-dev`
submodule; this repo carries the installer and non-agent dotfiles.

## Layout

- `skill-dev/` — private submodule (github.com/ui-HookeyChiang/skill-dev): canonical source for skills (repo-root skill dirs), `hooks/`, `scripts/`, `_shared/`, and `.claude/` (user-global config).
- `skill-dev/.claude/CLAUDE.md` — GLOBAL instructions (symlinked to `~/.claude/CLAUDE.md` by the installer). Edit in the submodule, never in `~/.claude/` directly.
- `skill-dev/.claude/docs/agents/` — docs `@imported` by the global CLAUDE.md.
- `.claude` — compat symlink to `skill-dev/.claude` (keeps installer whitelist paths stable). Not a directory; do not add files under it.
- The installer fans skill dirs out to `~/.claude/skills` and `~/.config/opencode/skills`, links `_shared` next to each fanout target, and initializes the submodule on fresh clones (`ensure_skill_dev_submodule`).
- No `.opencode/skill/` bridge — these skills reach OpenCode via the global fanout (`~/.config/opencode/skills`); a project bridge would duplicate. Documented as a wildcard accepted gap in `.agent-compat.json`.

## Development

- Never push directly to the default branch — all changes go through PRs.
- Develop in a linked worktree (`git worktree add .worktrees/<branch> -b <branch> origin/master`).
- After changing skills or config, run `bash skill-dev/agent-compat/scripts/check-compat.sh --scope project` — done when 0 gap(s).

## Issue tracker

Local markdown under `docs/ticket/` as `YYYY-MM-DD-<slug>.md` with a `Status:` line.
