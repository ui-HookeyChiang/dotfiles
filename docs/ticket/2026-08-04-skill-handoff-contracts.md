# One-directional handoffs: missing input contracts and close-the-loop pointers

Status: ready-for-agent

## Problem

Pipeline edges declared on only one side (template to copy: flow-dev's
`Input contract:` in description + `references/handoff-contract.json`):

1. `brief` — no input contract; never names flow-dev (producer) or flow-merge
   (successor). The flow-dev → brief → flow-merge chain has no declared edge.
2. `semver-release` — never names flow-merge as upstream nor states preconditions
   (clean tree / merged stack).
3. `skill-audit/SKILL.md:103-107` — report never routes findings back to
   skill-writer as the fix action; audit→write loop is implicit.
4. `verify-skill/SKILL.md:18-22` — when-NOT lists failure modes only; no routing
   "wanted an audit → skill-audit / wanted a score → darwin-skill".
5. `code-review` — no when-NOT in description; no input-contract statement in
   frontmatter (mode selection buried at body :41-42).

## Fix

Via `skill-writer`: add Input contract line + neighbor names to each description;
add one close-the-loop line to skill-audit's report template; add sibling routing
to verify-skill's when-NOT.

## Acceptance

Every stage in flow-dev → code-review/brief → flow-merge → semver-release →
release-publish and audit → write → verify names both neighbors.

## Origin

skill-guidelines flow-smoothness sweep, 2026-08-04. Severity: rough.
