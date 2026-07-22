# Standards Gate — DEV · standards-gate pre-flight

Before invoking `skill-creator`, every skill (`create` / `modify` /
`improve` / `rewrite`) MUST conform to the 8 standards below. This file is
the entry table; each row links to the full standard.

## Pre-flight checklist (8 standards)

| Standard | Summary | Full reference | Applies to | Voter served |
|---|---|---|---|---|
| description | description = triggering conditions only (no workflow summary) | [`description-standard.md`](description-standard.md) | all modes | A1 Trigger |
| contract | frontmatter required fields + eval artifact ≥ 16 cases + cross-ref syntax | [`contract-standard.md`](contract-standard.md) | all modes | A4 Contract |
| behavior | imperative voice + stage naming + constraint blocks + explicit if-then tables | [`behavior-standard.md`](behavior-standard.md) | all modes | A2 Behavior |
| adversarial | ≥ 3 pressure scenarios for any skill enforcing discipline | [`adversarial-scenarios.md`](adversarial-scenarios.md) | discipline-enforcing skills | A5 Adversarial |
| equivalence | classify change as equivalence-preserving or effect | [`equivalence-criteria.md`](equivalence-criteria.md) | modify / improve / rewrite | A3 Equivalence |
| trigger-eval | trigger-eval.json design (≥ 16 cases, ≥ 50% near-miss, realistic prose) | [`trigger-eval-design.md`](trigger-eval-design.md) | all modes | A1 Trigger |
| disclosure | main file vs references/ vs scripts/ split rules | [`disclosure-standard.md`](disclosure-standard.md) | all modes | A2 Behavior + prose-guidelines |
| e2e-baseline | 5-dimension AB measurement for rewrite mode | [`e2e-baseline-standard.md`](e2e-baseline-standard.md) | rewrite mode | A3 Equivalence (tool) |

## How to apply

1. Read each standard's `## Rules` section.
2. For each standard, decide: does my skill conform, or does it need
   `standard-override: <reason>` in frontmatter?
3. Record applied standards in frontmatter (DEV · self-check):
   `standards-applied: [description, contract, behavior, ...]`
   (advisory in v2; A4 Contract does not yet validate contents).
4. TEST · verify-skill 5-voter validates conformance.

## Rewrite mode addendum

For `rewrite` mode (v1 → v2), additionally read:

- [`equivalence-criteria.md`](equivalence-criteria.md) — decide if the change
  is equivalence-preserving or effect mode (auto-detect; user cannot declare).
- [`e2e-baseline-standard.md`](e2e-baseline-standard.md) — INTENT · E2E baseline A-capture
  protocol (no `--skip-e2e-baseline` escape hatch).

## Constraints

- DEV · standards-gate NEVER edits SKILL.md (only reads).
- Skipping the Standards Gate is a hard fail; verify-skill will catch
  missing `standards-applied:` in subsequent skill PRs once enforcement
  escalates from advisory to blocking.
