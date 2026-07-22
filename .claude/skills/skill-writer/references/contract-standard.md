# Contract Standard

Owns the **frontmatter structure**, the **eval artifact contract**, and
**cross-skill reference syntax**. Domain-disjoint from description-standard
(which owns description *content*).

## Rules

1. **Required frontmatter fields:** `name`, `description`. `name` must be
   letters / numbers / hyphens only (kebab-case); MUST match the directory
   name. `description` ≤ 1024 chars (see description-standard for content
   rules).
2. **Conditional frontmatter:** add `argument-hint` if the skill accepts
   arguments; add `test-devices` if the skill runs on hardware;
   `landing-group` for routing in skill landing UIs.
3. **Eval artifact:** `evals/trigger-eval.json` MUST have ≥ 16 cases
   (≥ 8 `should_trigger: true`, ≥ 8 `should_trigger: false`).
   `evals/adversarial-cases.json` is optional but recommended for any
   skill that enforces discipline.
4. **Cross-ref syntax:** reference other skills by name in prose, with a
   `REQUIRED` or `OPTIONAL` marker. **NEVER use `@`-prefix force-loads.**
   Reference depth ≤ 1 — do not link to another skill's `references/`
   file (depth-2 links confuse routing).
5. **`standards-applied:`** lists which of the 8 standards the skill
   conforms to (advisory).

## Examples

GOOD frontmatter:

```yaml
---
name: my-skill
description: Use when ...
argument-hint: "<create|modify> <target>"
test-devices: local
standards-applied: [description, contract, behavior, disclosure]
---
```

GOOD cross-ref (prose, marked):

```
Run `verify-skill` (REQUIRED) before merging. See `prose-guidelines`
(OPTIONAL) for paragraph compression.
```

## Anti-patterns

| Pattern | Why bad | What to do instead |
|---|---|---|
| `@skills/foo/SKILL.md` in body | force-loads the file regardless of need | drop `@`; mention by name + REQUIRED/OPTIONAL |
| Link to `skills/foo/references/x.md` | depth-2; reader can't tell intent | link to `foo` SKILL.md only; let foo decide what to surface |
| Missing `description` field | skill won't load | add it; see description-standard |
| `name` with underscores or capitals | breaks directory ↔ name match | use kebab-case to match the dir |
| trigger-eval.json with < 16 cases | A4 Contract REJECT | grow to ≥ 16 (see trigger-eval-design) |

## Override

Minimal. The frontmatter contract is repo-wide; overriding it breaks
loader tooling. If a skill genuinely needs an exotic field, declare
`standard-override: contract-rule-N (<reason>)`; A4 Contract will mark
the ballot NEEDS_HUMAN to force review.

## Validation

A4 Contract voter checks: frontmatter shape, required fields present,
eval artifact existence + ≥ 16 cases, cross-ref syntax (no `@`-loads,
depth ≤ 1).
