# Stage mechanics (skill-writer-specific)

## Borrow-vocab false-friend filter (rewrite / phase-reorg)

Rule: see `skill-guidelines` § Body-wide rules (borrow-vocab false-friend filter).
Application to skill-writer's own stage names:

When adopting an external model's stage/phase NAMES (e.g. the 8-stage
ideal-dev-workflow's INTENT/DEV/BUILD/TEST), check each borrowed term's contract
against the target domain BEFORE keeping it — "does the contract exist here?",
not "does the word sound right":
- **True fit** — contract holds → keep the name.
- **Degenerate fit** — contract exists but collapses → keep the name and mark the
  degeneration inline, traced to its premise. (DEV: a skill's red→green unit-test
  is N/A; its dev product is SKILL.md, verification lives in TEST.)
- **False friend** — contract does not exist → drop the stage, do not import it.
  (No BUILD stage for a skill: no fan-in artifact, no build-distinct-from-use; the
  8-stage "build is an INTERFACE" clause presupposes an artifact that a skill
  lacks — see ADR 0004.)

A degeneration clause ("artifact-less → trivial") authorizes keeping a stage only
while its premise holds; trace the premise before keeping a placeholder. No
detector — an authoring judgment, like the deletion-test (`skill-guidelines`
§ Body-wide rules).

## Two modes (body-routed, not a trigger-time switch)

**Writing** a skill (create / modify / rewrite) → apply `skill-guidelines`, then the
phase flow in SKILL.md — the build path. **Auditing / reading** an existing skill
(bloat, cross-skill duplication, dead code, "is this script still called") →
**read-only, no build**: dispatch to the matching audit engine via the SKILL.md
*Audit dispatch* table and stop; do NOT enter the phases.

The two are not exclusive: `rewrite` (a Writing sub-mode) *may* open with an Auditing
pass — audit v1 read-only for bloat / dead code / duplication, then feed those findings
into the v2 build (the natural "audit then rewrite skill X" path); the audit is a
recommended input to rewrite, not a required gate.

**Selection:** a build verb (create / modify / rewrite) or an absent target → Writing;
a bare audit/read verb on an existing skill → standalone Auditing.

Each audit engine is standalone and read-only (never edits / commits / builds). They
stay separate by design — three incompatible paradigms (metric scorer / LLM cross-file
/ pure graph) — but share one exit-code contract (stated inline in the SKILL.md *Audit
dispatch* table, the decision-time home). DEV static advisory dispatch inside the flow
(the `--no-llm` half) is a different thing: that runs skill-audit / prose-guidelines *during* a
build.
