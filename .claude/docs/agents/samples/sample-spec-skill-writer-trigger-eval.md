<!--
DRY-RUN SAMPLE — Pocock to-spec conversion shape. NOT published to GitHub Issues.
Source spec: docs/spec/archive/2026-06-02-skill-writer-trigger-eval-integration.md (shipped; archived)
Demonstrates how an engineering spec maps onto Pocock's spec template for the
active/proposed → Pocock migration. The real flow would `gh issue create` this
body with label `ready-for-agent`. Archived specs are NOT converted (frozen history).
-->

# Spec — skill-writer trigger-eval integration

## Problem statement (user perspective)

When I author a skill, skill-writer scores my description *statically* but never
checks whether it ACTUALLY triggers a live model. I find out my skill mis-fires
only after shipping — there is no dynamic trigger measurement in the flow.

## Solution (user perspective)

skill-writer gains an advisory Phase-5 step that runs my trigger corpus against
a live model and reports whether the description really fires the skill — plus a
mechanical frontmatter preflight. Both advisory: the deterministic verify-skill
gate stays the binding check; the live measurement never auto-passes or blocks.

## User stories

1. As a skill author, I want my trigger corpus run against a live model so I see
   the real fire/no-fire rate, so that I catch a mis-triggering description
   before merge.
2. As a skill author, I want a mechanical frontmatter validation so that a
   malformed `name`/`description` is caught programmatically, not by eyeball.
3. As a maintainer, I want these steps ADVISORY so that a non-deterministic
   live-LLM result can never auto-pass or auto-block a skill (human-is-the-floor).
4. As a maintainer, I want the integration to reuse the existing dogfood/TDD
   trace machinery so that "did it run?" is auditable, not a memory question.

## Implementation decisions (interface / contract level — NO file paths)

- Two of skill-creator's eight scripts integrate (`run_eval`, `quick_validate`);
  the other six stay out (anti-self-grading boundary).
- `run_eval` → Phase 5, advisory, trace-required; `quick_validate` → Phase 4
  preflight, advisory.
- A 4-layer resolver locates the upstream skill-creator plugin (override →
  installed-plugins manifest → fd fallback → package-marker validation).
- New trace token in the sandwich-log grammar:
  `gate=trigger-eval:skill-writer … verdict=<ok|fail|skip-…>`.
- Graceful advisory skips: unresolvable skill-creator / no-corpus / no-auth all
  trace a skip, never a hard fail or a fake all-False.
- **Hard invariant:** run_eval output is a measurement ONLY — never wired into a
  description mutator (that would rebuild the rejected `run_loop`).

## Testing decisions

- Advisory steps proven by trace presence + graceful-skip cases, not by gating.
- verify-skill Phase 6 remains the binding deterministic gate.

## Out of scope

- The other six skill-creator scripts.
- Any auto-rewrite driven by run_eval output.

## Blocked by

None — can start immediately. (`ready-for-agent`)

---

### Conversion notes (meta — for the migration, not part of the spec)

- The source spec's `## Purpose`/`## Why now` → spec Problem/Solution (user-framed).
- `## Scope In scope` numbered items → Implementation Decisions, stripped of
  file paths per to-spec's anti-staleness rule (paths go stale; the decision is
  the contract).
- The `[[feedback_darwin_self_scoring_pattern]]` memory link + anti-self-grading
  rationale → a User Story (#3) + the hard invariant, since they are acceptance
  constraints not impl detail.
- Engineering-spec sections with no spec-template home (the 4-layer resolver mechanics,
  exact trace grammar) → kept under Implementation Decisions as
  decision-encoding detail (the one to-spec exception: a contract-precise snippet
  is allowed when prose would lose precision).
- This shows the SHAPE. A real run would publish via `gh issue create` with the
  `ready-for-agent` label; ADR-worthy decisions (the anti-self-grading boundary)
  would also get a `docs/adr/` entry.
