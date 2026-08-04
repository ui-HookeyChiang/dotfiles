# Dead skill-name pointers across non-ubiquiti skills

Status: ready-for-agent

## Problem

Two references point at skills that do not exist on any skill root:

1. `brief/SKILL.md:11-12` → `receiving-code-review` (nowhere on disk).
2. `model-eval/SKILL.md:125` → `deep-research` (nowhere on disk).

Not dead (audit false positive, corrected 2026-08-04): `flow/SKILL.md` references
to `to-spec` / `to-tickets` are current — both resolve at `~/.claude/skills/`
(symlinks to `~/.agents/skills/`). The `to-prd` / `to-issues` copies under
`~/.claude/skill-dev/.agents/skills/` are stale pre-rename leftovers; consider
deleting them there so future audits don't trip on the same shadow.

## Fix

Via `skill-writer` (modify mode): repoint or delete each dead reference.
For brief, route "responding to feedback" to an existing skill or drop the line.
For model-eval, route published-benchmark research to `research` only.
Optionally: remove stale `to-prd` / `to-issues` from skill-dev's `.agents/skills/`.

## Acceptance

Every skill name referenced in these files resolves under `.claude/skills/`,
`~/.claude/skills/`, or plugins.

## Origin

skill-guidelines flow-smoothness sweep, 2026-08-04. Severity: BROKEN (pointers), minor.
