# install.sh: full skill-dev installer parity from snapshot

Status: ready

## Blocked by

- `docs/ticket/sync-full-parity-paths.md`

## Goal

Extend `dotfiles/install.sh` so that (given the complete `.claude/` snapshot
from the sync ticket) it reproduces the effects of
`~/.claude/skill-dev/install.sh` for Claude, OpenCode, and Cursor — WITHOUT
touching the existing zsh/tmux/nvim/system sections. Source for all installed
artifacts is the repo snapshot (`$DOTFILES/.claude/...`), not the skill-dev
checkout.

Reference implementation to port from: `~/.claude/skill-dev/install.sh`
(read it fully; reuse its logic, adapted to snapshot paths). Where skill-dev
ships helper scripts that the snapshot now contains
(`.claude/hooks/register-settings-hooks.sh`, `.claude/hooks/lib/`,
`.claude/scripts/register-harness.sh`, `.claude/scripts/lib/agent-detect.sh`,
`.claude/scripts/skills-lock.sh`, `.claude/hooks/manifest.json`), CALL them
rather than re-porting their logic.

## Scope

Add a Claude/agents install section (new function(s) + flags, mirroring the
existing `--with-*` style; pick a sensible default consistent with how
CLAUDE_FILES are installed today):

1. **Skills symlink** — symlink every dir under `.claude/skills/` into
   `~/.claude/skills/`, plus fanout symlinks to
   `~/.config/opencode/skills/` and `~/.agents/skills/` (codex/cursor), same
   as skill-dev install.sh. Skip/replace existing symlinks; back up real dirs
   with the existing timestamped-backup pattern.
2. **Agent definitions** — symlink `.claude/docs/agent-definitions/*.md` into
   `~/.claude/agents/` and `~/.config/opencode/agents/`.
3. **Hook registration** — symlink `.claude/hooks/*.sh` into
   `~/.claude/hooks/` and register into `~/.claude/settings.json` per
   `.claude/hooks/manifest.json`, by invoking the snapshot's
   `register-settings-hooks.sh` / registration engine (adapt paths via env or
   args if the script assumes repo layout — prefer minimal patching at sync
   time over forking logic).
4. **docs/agents symlinks** — symlink `.claude/docs/agents/*.md` into
   `~/.claude/` absent-only, and support CLAUDE.md `@`-include registration as
   skill-dev's `--register-claudemd` does (dotfiles already ships CLAUDE.md
   with @-includes — verify and no-op if already present).
5. **`--sync-settings` equivalent** — merge `.model` and
   `.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` into `~/.claude/settings.json`
   (jq merge, preserve other keys). Match skill-dev's values/behavior.
6. **`--register-cursor` equivalent** — write `.cursor/rules/*.mdc` and merge
   `.claude/hooks/cursor/user-settings.json` / `cli-config.json` into Cursor's
   settings, porting skill-dev's logic against snapshot paths.
7. **OpenCode config merge** — symlink `.claude/hooks/opencode/skill-dev-hooks.ts`
   plugin and merge instructions/plugin/agent registration into
   `~/.config/opencode/opencode.json`, porting skill-dev Phase 6.
8. **Extras** — install `rtk` (with its hook registration) and the
   lock-pinned GitHub skills (darwin-skill, nuwa, mattpocock) driven by
   `.claude/skills-lock.json` via the snapshot's `skills-lock.sh`, replacing
   the current unpinned `npx skills add` path in `install_skills()`.
9. **Verification phase** — after install, run agent-parity check
   (`~/.claude/skills/agent-parity/scripts/check-parity.sh` via the snapshot)
   and skills-lock verify; non-zero exit prints warnings but does not abort
   install (match skill-dev behavior).

Constraints:
- zsh/tmux/nvim/system package sections byte-identical (no diff outside the
  new/changed Claude-related functions and flag wiring, other than
  `install_skills()` replacement).
- Everything must work when `~/.claude/skill-dev` does NOT exist (fresh
  machine, dotfiles only).
- `ubiquiti-*` never appears (snapshot already excludes; don't re-add).
- Idempotent: second run makes no changes and no duplicate settings.json hook
  entries / opencode.json entries / CLAUDE.md includes.

## Test plan

- Sandbox run: fake home (env-overridable target dirs; add minimal env
  overrides if needed for testability) → run the new section → assert:
  - `~/.claude/skills/<name>` symlinks exist for every snapshot skill; none
    ubiquiti-*; fanout links in `~/.config/opencode/skills`, `~/.agents/skills`.
  - `~/.claude/agents/*.md` and `~/.config/opencode/agents/*.md` present.
  - `~/.claude/settings.json` has hook entries matching manifest.json events.
  - `~/.config/opencode/opencode.json` has plugin + instructions merged.
  - Cursor rules files written.
- Idempotency: run twice, diff target tree — identical, no duplicated JSON
  array entries.
- `bash -n install.sh` passes; `git diff` shows zsh/tmux/nvim sections
  untouched.
- Compare against skill-dev result where feasible: run skill-dev install.sh
  into another fake home, diff the ~/.claude trees (symlink targets differ by
  design — compare link names + resolved content, not link paths).

## Test seam

Shell-level against a fake `$HOME`/target-dir override. No unit framework.

## Hook registration evidence (follow-up verification)

Decision: `--register-hooks` stays a separate opt-in flag, not folded into
`--with-claude-agents` by default. This matches skill-dev's own install.sh,
which also defaults `REGISTER_HOOKS=0` and requires `--register-hooks`
explicitly (skill-dev install.sh:93,104) — hooks are symlinked unconditionally
but only merged into settings.json/hooks.json when the flag is passed. No
code change needed; the earlier test run simply hadn't passed the flag.

Evidence, fresh fake HOME, `install_claude_agents` with `REGISTER_HOOKS=1`:
- `manifest.json` defines 7 hooks with a `claude` harness (block-main-edit,
  guard-stale-base, guard-agent-worktree-files, guard-agent-worktree-bash,
  block-bare-read, block-heredoc-continuation, subagent-dispatch-inject) —
  no `SessionStart` entries exist for the claude harness in manifest.json.
- After one run: `~/.claude/settings.json` has all 7, as 6 `PreToolUse`
  entries + 1 `SubagentStart` entry — exact match.
- `~/.cursor/hooks.json` got the 5 manifest entries with a `cursor` harness
  (rtk is codex-only, absent as expected since codex wasn't detected).
- Idempotency: ran twice; `diff` of settings.json before/after run 2 is
  byte-identical (0 differences) — no duplicate hook entries.
  register-settings-hooks.sh logs `[merged]` on every `--apply` run
  regardless of whether content changed (that's the snapshot script's own
  behavior, unmodified) — the diff, not the log line, is the source of
  truth for no-duplication.
