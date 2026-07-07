# Harness Diagnosis (2026-07-06, Fable 5 session)

Top three defects in this harness, by cost. Each: evidence → cost → fix.
Referenced by: CLAUDE.md, model-dispatch.md, maintenance.md.

## 1. Primary workflow route was broken (top error source)

**Evidence:** CLAUDE.md routed all code changes to `stacking-dev`. That skill was
renamed/split in skill-dev PRs #958–#962 into `stack` (pipeline orchestrator),
`stack-dev` (per-change workflow), `stack-merge` (cascade merge). The symlink
`~/.claude/skills/stacking-dev` dangled; the three new skills were never linked
into `~/.claude/skills/`, so no session could load them.

**Cost:** Every code-change session since the rename either stalled hunting for a
nonexistent skill or silently improvised outside the workflow (no sizing, no
stacked PRs, no independent review) — the exact failure the rule existed to prevent.

**Fix (applied 2026-07-06):** removed dangling symlink, linked `stack`,
`stack-dev`, `stack-merge` into `~/.claude/skills/`; CLAUDE.md now routes to
`stack-dev`. **Prevention:** skill-rename checklist in `maintenance.md`, plus
the broken-symlink check below.

Check to run whenever a routed skill is missing (safe, read-only):

```bash
for l in ~/.claude/skills/* /home/hookey/dotfiles/.claude/skills/*; do
  [ -e "$l" ] || echo "BROKEN: $l"
done
```

## 2. Skill-catalog bloat (top token leak)

**Evidence:** ~250 skill descriptions load into every session's system prompt:
~20 `*-perspective` + council skills symlinked from
`/home/hookey/stock-target-finder/skills/` into global `~/.claude/skills/`,
37 `thinking-*` skills symlinked in `dotfiles/.claude/skills/` (project-scoped
to dotfiles sessions), the full `pua` plugin AND standalone pua copies in
`~/.agents/skills/` (duplicates visible in the loaded list: `pua` vs `pua:pua`,
`caveman` vs `caveman:caveman`, `skill-creator` vs `skill-creator:skill-creator`).

**Cost:** roughly 15–25k tokens burned per session before the first user word —
in EVERY session, including quick questions. Second-order cost: near-duplicate
descriptions make weaker models mis-trigger (e.g. `pua:p7` vs `p7`).

**Fix (needs user decision — do not apply unilaterally):**
- Move `stock-target-finder` perspective symlinks out of global
  `~/.claude/skills/` into that project's own `.claude/skills/` (they only
  matter there).
- Remove `thinking-*` symlinks from `dotfiles/.claude/skills/` if not pulling
  their weight in dotfiles sessions (they also ship as a plugin manifest in
  `cc-thinking-skills/.claude-plugin/` — check both sources).
- Pick ONE source per duplicated skill: either the plugin (`pua@pua-skills`,
  `caveman@caveman` in settings.json `enabledPlugins`) or the symlink in
  `~/.agents/skills/`-backed `~/.claude/skills/`; disable the other.
- `~/.claude/skills-disabled/` exists as the parking lot (currently holds
  `thinking-council`).

## 3. Stale model pins + contradictory delegation rules (top focus-loss)

**Evidence:** Old CLAUDE.md pinned subagents to `claude-sonnet-4-6` (superseded;
a pinned ID goes stale, an alias doesn't). Simultaneously: "routes all changes,
including small single-file fixes, through the full flow" + "Always delegate
execution to subagents" (Workflow section) vs "main agent … handles single-file
changes directly" (Delegation section).

**Cost:** A weaker model resolves contradictions by recency or mood — the same
task gets the full pipeline one day, an inline edit the next. Stale model IDs
fail agent spawns or silently fall back.

**Fix (applied):** rewritten CLAUDE.md has one sizing rule and no pinned IDs;
`model-dispatch.md` uses aliases (`sonnet`/`opus`/`haiku`) only.

## Honorable mentions (real, not top-3)

- **No subagent report contract** — agents returned prose dumps into the main
  context. Fixed by the contract in `model-dispatch.md`.
- **Mandatory-skill landmines** — `using-superpowers` demands invocation "before
  ANY response", `brainstorming` "MUST use before any creative work". These
  hijack turns on trivial requests. Old CLAUDE.md already subordinated them to
  the workflow skill; the rewrite keeps that.
- **Safety rests on thin mechanics** — `defaultMode: bypassPermissions` +
  `Bash(*)` allow means "never push to main" is enforced only by
  `block-main-edit.sh` (matches Edit/Write tools, not bash-side writes) and a
  deny list that blocks force-push but NOT `git push origin main`. The
  CLAUDE.md safety section is load-bearing; see letter-to-future-sessions.md §1.

## Honest limits

This diagnosis covers mechanics (routes, tokens, contracts). What no file can
fix: ambiguous requirements and taste-level judgment. The protocol for those is
in `judgment.md` ("Honest limits") — escalate model, get a second opinion, or
tell the user it needs them. Do not fake confidence.
