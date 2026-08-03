# Extend sync-to-dotfiles to copy all install.sh dependencies

Status: ready

## Blocked by

None.

## Goal

`dotfiles/install.sh` will reproduce skill-dev `install.sh`'s effects from the
snapshot under `dotfiles/.claude/`. Today the sync script copies only
`hooks/*.sh` (+ `hooks/tests`), skills, and `docs/agents/` — missing every
other path skill-dev's installer depends on. Extend
`.claude/skills/sync-to-dotfiles/scripts/sync-to-dotfiles.sh` so the snapshot
is complete, then run it and commit the resulting snapshot.

Source of truth: `~/.claude/skill-dev` (read-only reference; use a clean
worktree off `origin/main` when applying). Reference installer:
`~/.claude/skill-dev/install.sh`.

## Scope

Add to the sync (all one-way skill-dev → `dotfiles/.claude/`, ubiquiti-*
skills stay excluded):

1. **Full `hooks/` tree** — replace the `hooks/*.sh` glob with a recursive
   copy of `hooks/` including `hooks/lib/`, `hooks/manifest.json`,
   `hooks/opencode/` (e.g. `skill-dev-hooks.ts`), `hooks/cursor/`
   (`user-settings.json`, `cli-config.json`), `hooks/tests/`.
2. **`docs/agent-definitions/`** — all files, recursively.
3. **Registration toolchain** — `scripts/register-harness.sh`,
   `scripts/lib/agent-detect.sh`, `scripts/skills-lock.sh` (copy the whole
   `scripts/` dir if simpler, but exclude anything skill-dev-repo-specific
   that install.sh does not use — check install.sh references first).
4. **`agent-parity/scripts/check-parity.sh`** (agent-parity is also a skill
   dir with SKILL.md — already synced as a skill; verify the script rides
   along via the skill copy; if so just assert, don't duplicate).
5. **`skills-lock.json`** (repo root → `dotfiles/.claude/skills-lock.json`).

Keep: dry-run default, `--apply`, `SRC`/`DST` overrides, per-section counts in
summary, leaves dotfiles uncommitted. After the script change is committed,
run `--apply` from a clean skill-dev worktree and commit the refreshed
snapshot as a separate commit (`chore(claude): refresh skill-dev snapshot`).

## Test plan

- `bash .claude/skills/sync-to-dotfiles/scripts/sync-to-dotfiles.sh` (dry run)
  lists all new sections with non-zero counts and writes nothing
  (`git status --porcelain` unchanged).
- Run with `--apply` from a clean skill-dev worktree
  (`git -C ~/.claude/skill-dev worktree add /tmp/sync-src origin/main`,
  `SRC=/tmp/sync-src`); verify presence of: `.claude/hooks/lib/`,
  `.claude/hooks/manifest.json`, `.claude/hooks/opencode/`,
  `.claude/hooks/cursor/`, `.claude/docs/agent-definitions/*.md`,
  `.claude/scripts/register-harness.sh`, `.claude/skills-lock.json`.
  Remove the worktree after (`git -C ~/.claude/skill-dev worktree remove
  /tmp/sync-src --force`).
- No `ubiquiti-*` dir appears under `.claude/skills/`.
- Idempotent: second `--apply` produces no further git diff.

## Test seam

Shell-level: run the script (dry + apply) against the real skill-dev worktree
and assert on filesystem/git state. No unit framework in this repo.
