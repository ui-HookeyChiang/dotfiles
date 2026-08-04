# Dead skill-name pointers across non-ubiquiti skills

Status: ready-for-agent

## Problem

Four references point at skills that do not exist on any skill root:

1. `brief/SKILL.md:11-12` → `receiving-code-review` (nowhere on disk).
2. `model-eval/SKILL.md:125` → `deep-research` (nowhere on disk).
3. `flow/SKILL.md:123` → `to-spec`; actual upstream skill is `to-prd`.
4. `flow/SKILL.md:100,137` → `to-tickets`; actual upstream skill is `to-issues`.

Note: root `.claude/CLAUDE.md` routing table also uses `to-spec` / `to-tickets` —
decide whether to rename table rows or alias the upstream skills; keep table and
flow/SKILL.md consistent either way.

## Fix

Via `skill-writer` (modify mode): repoint or delete each dead reference.
For brief, route "responding to feedback" to an existing skill or drop the line.
For model-eval, route published-benchmark research to `research` only.

## Acceptance

Every skill name referenced in these files resolves under `.claude/skills/`,
`~/.claude/skills/`, or plugins; routing table and flow body agree.

## Origin

skill-guidelines flow-smoothness sweep, 2026-08-04. Severity: BROKEN (pointers), minor.
