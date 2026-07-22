# Behavior Standard

Owns the SKILL.md **body** — how phases are written, ordered, and
constrained. Domain-disjoint from description-standard (header) and
contract-standard (frontmatter).

## Rules

1. **Imperative voice.** "Run X", "Check Y", "Stop on failure". Never
   "You should ..." or "It is recommended to ...". Imperatives compile to
   action; hortative voice compiles to suggestion (which Claude rationalizes
   past under pressure).
2. **Stage / phase naming.** Skills using the 3-stage INTENT/DEV/TEST model label
   sections as `## Stage N — INTENT/DEV/TEST`. Skills using an ordinal-phase model
   use `Phase 1 / Phase 2 / Phase 3 ...` with sub-steps `1a / 1b / 1c`;
   `Phase 0` is reserved for pre-flight gates (e.g. E2E Baseline) in those skills.
   skill-writer itself uses 3-stage INTENT/DEV/TEST (ADR 0004).
3. **Stage/phase order is part of behavior.** Reordering stages or phases is an
   effect-mode change (A3 Equivalence will catch it). Gate decisions and `blockedBy`
   chains live inside the stage/phase definitions.
4. **Constraint blocks end every stage/phase.** Format:
   `> Stage N constraints:` (or `> Phase N constraints:`) followed by
   `- never X` / `- always Y` bullets.
   At least one `never` and one `always`. Constraints make the rules
   reviewable in isolation from the prose.
5. **Explicit if-then table for any branch.** Use a table listing ALL
   cases. Never an "otherwise ..." fallback — explicit beats implicit.
6. **Failure modes per stage/phase.** Each stage or phase lists what failure looks like
   and the remediation (next stage/phase to re-enter, or STOP).

## Examples

BEFORE (hortative, no constraint block):

```markdown
## Phase 5

It is recommended to refresh the evals after modifying SKILL.md.
You should add at least 16 cases.
```

AFTER (imperative + table + constraint block):

```markdown
## Phase 5: Eval Refresh

1. Read updated description.
2. Regenerate `evals/trigger-eval.json` to ≥ 16 cases.
3. Run `make lint` to confirm.

| Outcome | Next |
|---|---|
| Lint pass | Phase 6 |
| Lint fail | fix evals; re-enter Phase 5 |

> Phase 5 constraints:
> - never auto-commit eval files
> - always include ≥ 8 positive AND ≥ 8 negative cases
```

## Anti-patterns

| Pattern | Why bad | What to do instead |
|---|---|---|
| "You should ..." | hortative — rationalized away under pressure | imperative ("Run ...", "Stop on ...") |
| Missing constraint block | rules buried in prose, ignored on re-read | add `> Phase N constraints:` with never/always |
| Implicit "otherwise" fallback | reader fills in the wrong default | explicit table with ALL cases |
| Sub-steps as `Phase 5.1` | numbered like top-level phase; A3 Equivalence may flag as new phase | use `5a / 5b / 5c` |
| Phase 0 used for normal first phase | Phase 0 is reserved for pre-flight gates | start at Phase 1 |

## Override

Rare. Workflow skills with genuinely free-form steps (e.g. exploratory
brainstorming) may relax Rule 3 (phase order). Declare
`standard-override: behavior-rule-3 (free-form exploration)`; A2 Behavior
will inspect for compensating discipline.

## Validation

A2 Behavior voter reads SKILL.md and exercises a scenario; checks
imperative voice, phase coherence, constraint blocks present, if-then
tables explicit. Hortative voice + missing constraint blocks are the most
common REJECT cause.
