# References Index

This directory is the Source of Single Truth (SSOT) for skill authorship
standards in this repo. `skill-writer` reads these files during DEV · standards-gate
to ensure every skill (new or rewritten) conforms.

## Files

| File | Purpose | Voter served |
|---|---|---|
| `INDEX.md` | Domain map + conflict resolution | (meta) routing for all 14 |
| `standards-gate.md` | DEV · standards-gate pre-flight checklist (summary of 8 standards) | (meta) entry table |
| `description-standard.md` | Pure-trigger description content rules | A1 Trigger |
| `contract-standard.md` | Frontmatter + eval artifact + cross-ref syntax | A4 Contract |
| `behavior-standard.md` | SKILL.md body imperatives + stage order + constraints | A2 Behavior |
| `adversarial-scenarios.md` | Pressure-scenario library | A5 Adversarial |
| `equivalence-criteria.md` | v1 vs v2 equivalence determination | A3 Equivalence |
| `trigger-eval-design.md` | trigger-eval.json design principles | A1 Trigger (strengthens) |
| `disclosure-standard.md` | main file vs references/ vs scripts/ split | cross-voter (A2 + prose-guidelines) |
| `e2e-baseline-standard.md` | rewrite mode AB test 5 dimensions | A3 Equivalence (tool) |
| `phase-4-tools.md` | DEV static advisory + TEST LLM-review audit tool invocation details | (stage-specific) |
| `content-placement-scan.md` | Rewrite-mode whole-skill content-placement brief (MIGRATE / SLIM / HOLD-IN-PLACE) + orchestrator override | (stage-specific) |
| `phase-6-gate.md` | TEST · verify-skill 5-voter exit code + ballot SOP + why-gate evidence | (stage-specific) |
| `skill-flow-testing.md` | TEST · 5b skill-flow-execution: run skill flow on device/local | (stage-specific) |

## Domain map (who owns what)

| Standard | Owns |
|---|---|
| description-standard | description content + trigger behavior |
| contract-standard | frontmatter required fields + eval artifact + cross-ref syntax |
| behavior-standard | SKILL.md body imperative format + **phase order** + constraint blocks |
| equivalence-criteria | v1 vs v2 equivalence determination |
| e2e-baseline-standard | rewrite mode AB test dimensions |
| adversarial-scenarios | pressure scenario library |
| trigger-eval-design | trigger-eval.json design principles |
| disclosure-standard | what lives in main file / references/ / scripts/ |

## Conflict resolution rule

When two standards conflict on a rule, the **owner of the relevant domain
wins** (lookup in the table above). If both standards claim ownership of
the same domain, treat it as a **standard-design bug** — fix `INDEX.md`
before merging any change.

## Dependency graph

- `description-standard` ← `trigger-eval-design` (eval exercises description)
- `contract-standard` owns the `description:` frontmatter field; `description-standard` owns its content
- `equivalence-criteria` → `e2e-baseline-standard` (AB test is the measurement tool)
- `adversarial-scenarios` → `behavior-standard` (scenarios test constraint blocks)
- `disclosure-standard` ← all skills (governs main-vs-references-vs-scripts split)
- `phase-4-tools` and `phase-6-gate` are skill-writer-internal stage docs; do not own any voter
- `skill-flow-testing` is skill-writer-internal stage doc (TEST · 5b); does not own any voter

## How skill-writer reads this

DEV · standards-gate reads `standards-gate.md` first.
`standards-gate.md` references each detailed standard file. Skills override
individual standards via frontmatter `standard-override: <reason>`; the
override must survive Adversarial voter scrutiny.
