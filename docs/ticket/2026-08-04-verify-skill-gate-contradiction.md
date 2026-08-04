# skill-writer ↔ verify-skill: gate optionality contradiction + stale "Phase 6" vocabulary

Status: ready-for-agent

## Problem

1. `skill-writer/SKILL.md:65,71` marks verify-skill OPTIONAL (†) for modify mode,
   while `verify-skill/SKILL.md:3,14` self-describes as "The mandatory skill-writer
   Phase 6 quality gate". The two documents disagree on whether the gate can be skipped.
2. "Phase 6" / "Phase 4" vocabulary is stale — skill-writer now uses 3 stages
   INTENT/DEV/TEST (ADR 0004), yet `references/phase-6-gate.md` / `phase-4-tools.md`
   filenames and mentions persist (`skill-writer/SKILL.md:241,249`).

## Fix

Pick one truth (recommend: keep modify-mode optionality, fix verify-skill's
self-description to say "mandatory for create/rewrite, optional for small modify"),
then rename stale phase references to stage vocabulary.

## Acceptance

- No contradiction between the two SKILL.md files on gate optionality.
- `grep -ri 'phase.?[46]' .claude/skills/skill-writer .claude/skills/verify-skill`
  returns nothing (or only historical ADR citations).

## Origin

skill-guidelines flow-smoothness sweep, 2026-08-04 (toolchain cluster). Severity: rough.
