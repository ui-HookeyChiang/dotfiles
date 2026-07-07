# Maintenance Protocol for .claude/ Institution Files

Covers: CLAUDE.md, model-dispatch.md, judgment.md, delegation-templates.md,
harness-diagnosis.md, maintenance.md (this file), letter-to-future-sessions.md.
All changes go through a worktree branch + PR (the `block-main-edit` hook
enforces this; do not bypass with `ALLOW_MAIN_EDIT=1` or bash-side writes).
Backup before rewrite: `cp <file> ~/.claude/backups/<file>.bak-$(date +%s)`.

## What you may change without asking the user

- Fix factually wrong content with evidence in hand: dead paths, renamed
  skills, stale tool names, broken commands. Cite the evidence in the commit.
- Append a lesson (format below) to the file whose rule failed.
- Add a positive/negative example to an existing judgment rubric.
- Repair broken symlinks in `~/.claude/skills/` when git history shows the
  rename (the stacking-dev incident pattern).

## What requires asking the user first

- Anything in CLAUDE.md **Safety** (push/merge/release rules) — never touch.
- Changing a routing target (e.g. replacing `stack-dev` with something else).
- Deleting or weakening any rule, rubric, or template — even ones that seem
  obsolete; propose removal with reasoning instead.
- Changing model-selection defaults or the report contract.
- Skill-catalog pruning (harness-diagnosis §2) — user decision.

## Where lessons go

Follow `memory-discipline.md`'s gate FIRST (hook/deny > ADR > issue > MEMORY).
Only lessons about *how these institution files themselves fail* land here, as
an appended entry in the affected file under a `## Lessons` heading:

```
- 2026-07-06 · trigger: skill routed in CLAUDE.md not in loaded list ·
  lesson: renames in skill-dev must update symlink + CLAUDE.md route ·
  action taken: added rename checklist below
```

One line, dated, with a concrete trigger condition — a lesson without a
trigger is decoration and gets pruned.

## Skill-rename checklist (from the stacking-dev incident)

When a skill is renamed/split/retired in skill-dev:
1. Update or remove its symlink in `~/.claude/skills/` (and
   `dotfiles/.claude/skills/` if present).
2. `rg <old-name> /home/hookey/dotfiles/.claude/` — fix every route/mention.
3. Run the broken-symlink check (harness-diagnosis §1).
4. Start a new session or reload and confirm the new name appears in the
   loaded skill list.

## Compaction rule (prevents re-bloat)

Trigger: any of these files exceeds ~120 lines, or a `## Lessons` section
exceeds 8 entries, or two rules overlap >50% in meaning.
Action: propose a compaction PR — merge overlapping rules, fold ratified
lessons into the rule text they amended, drop examples that no longer earn
their tokens. Keep at most one positive + one negative example per rubric.
CLAUDE.md itself must stay under ~60 lines: it is a router, and every line in
it taxes every future session.
