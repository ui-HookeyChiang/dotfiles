# Trigger collisions: missing tiebreakers between sibling skills

Status: ready-for-agent

## Problem

First-match routing collisions with no cross-pointer in at least one direction:

1. **skill-writer vs darwin-skill** — skill-writer claims `improve` = modify
   (`skill-writer/SKILL.md:83`); darwin-skill's description claims 「帮我改改skill」/
   「提升skill质量」/"skill review". darwin never defers back to skill-writer.
2. **adversarial-review vs thinking-council / investment-research-council** —
   "premortem" and "epistemic audit" appear verbatim in both descriptions; no
   cross-pointer either direction. adversarial-review explicitly rejects persona
   role-play; councils are persona fan-out for the same phrases.
3. **semver-release vs release-publish** — bare "release" has no tiebreaker;
   semver-release has no when-NOT section at all. (release-publish:159 already
   points back — keep.)

## Fix

Add when-NOT / defer lines in descriptions (routing-visible, not body-only):
darwin defers non-rubric edits to skill-writer; adversarial-review vs councils
state the persona/no-persona split mutually; semver-release gains a when-NOT
("notes/announce → release-publish").

## Acceptance

Each colliding phrase has exactly one winning skill, with the loser's description
naming the winner.

## Origin

skill-guidelines flow-smoothness sweep, 2026-08-04. Severity: rough.
