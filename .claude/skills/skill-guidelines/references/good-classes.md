# Good-Classes — What Belongs in a SKILL.md Body

A SKILL.md body is a closed set: it contains only these six good-classes.
Anything outside them is what an auditor would flag — keep it out at write
time rather than purge it later.

## 1. Triggers / routing

When to use, when NOT (NOT-clauses), how to pick a mode. The description is
trigger-only and enumerates edge-case triggers + violation symptoms.
(Pre-empts: description-standard / verify-skill A1)

## 2. Contracts

Inputs, outputs, exit codes, side-effects, ordering, invariants; frontmatter;
cross-ref `REQUIRED:`/`OPTIONAL:` markers (never `@`-prefix); execution-intent
(execute vs read-as-reference); dependency declarations.
(Pre-empts: contract-standard / behavior-standard)

## 3. Live-mechanism instructions

The critical-path steps the agent runs NOW: intent prose + script invocations.
"Live" means a real referent exists in `scripts/` or the live skill — a claim
with zero live referent is a phantom mechanism; do not write it. A fixed chain
of 3+ commands belongs in `scripts/` (the body states intent, the script
executes). No change-history in the body — migrations/changelogs/dated "moved
from" belong in git + spec.
(Pre-empts: `behavior_mismatch` `kind=stale` phantom-mechanism + G8
`inline_changelog`; scriptifiable Detector 2)

## 4. Preconditions / caveats

Guards, gotchas, boundary conditions that change behavior; security ("lack of
surprise"); dependency availability. Never cut a precondition/caveat/contract/
NOT-clause to hit a line target — those are facts (retention guardrail — SSOT:
`prose-guidelines` Gate 7).

## 5. Disambiguation

"X vs Y", which to pick, NOT-this-skill, when NOT to create a skill at all.

## 6. Pointers

To `references/` (detail; add a TOC if > 100 lines), `scripts/` (execution),
sibling skills (by name + marker), live specs; organize multi-domain skills by
domain variant. Keep the critical path inline; push rationale and long examples
to `references/`.
(Pre-empts: size/imbalance/staleness composite / G8 progressive-disclosure)

## Body-wide rules

- **Say a thing once** — within-file prose dedup is generic prose
  (`prose-guidelines`, "cut what does no work"); cross-skill dedup is
  `skill-audit` G1. Consolidate or cite the single home.
- **Deterministic before probabilistic** — order checks deterministic-first;
  decide the concept's shape (closed / open+signal / open-no-signal). SSOT:
  `coding-guidelines` §6.
- **Mnemonic codes** — a coined finding-code/gate-token decodes its meaning.
  SSOT: `coding-guidelines` § Naming.
- **Deletion-test a phase** (rewrites) — before promoting a step to a top-level
  phase, delete it: does the work vanish or reappear next phase?
- **Borrow-vocab false-friend filter** — when adopting an external model's
  stage NAME, confirm its contract exists here; drop the stage if it doesn't.
- **Delegate reasoning, keep mechanism** — when a skill orchestrates multiple
  stages, each stage's reasoning (how to grill, how to decompose, how to TDD)
  belongs in the invoked skill, NOT inline. The body keeps: (a) which skill to
  invoke, (b) what input to pass, (c) gate condition after it returns.
  Litmus test: if you delete the inline reasoning and replace it with
  `Invoke Skill X`, does behavior change? No → delegate. Yes → it is a
  precondition/contract (good-class 4) or disambiguation (good-class 5), keep it.
