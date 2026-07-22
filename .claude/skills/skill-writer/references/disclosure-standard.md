# Disclosure Standard

Owns the **main file vs `references/` vs `scripts/`** split. Cross-cuts
A2 Behavior (critical path must be in main) and prose-guidelines (main file
length budget).

## Rules

1. **Critical path stays in SKILL.md.** Stage/phase order, conditional branches,
   gate decision tables, `never X` / `always Y` constraints, every-
   invocation details. If Claude needs it on every invocation, it lives in
   the main file.
2. **Reference path goes to `references/`.** Complete error code tables
   (main file keeps a 3-class summary), historical evidence, JSON
   schemas, multi-variant examples, full prompt templates.
3. **Script path goes to `scripts/`.** Any deterministic check, repeated
   invocation template, anything that should be run rather than read.
4. **Single-line decision rule.** "If this detail is needed every
   invocation → main file; otherwise → `references/`."
5. **Token cost budget.** Main `SKILL.md` targets ≤ 500 lines for non-
   getting-started skills; ≤ 200 lines for frequently loaded skills
   (e.g. routers and dispatchers).

## Examples

BAD: `skill-writer/SKILL.md` v1 verify-skill gate section = 90 lines (full exit-code table
+ env-var fallback + dogfood evidence inline). Result: main file 480
lines, agents skim past the critical "never auto-commit" constraint.

GOOD: v2 TEST · verify-skill section ~ 30 lines (gate decision + exit code 3-class summary +
`> constraints` block) with a link to
[`phase-6-gate.md`](phase-6-gate.md) for the 9-exit-code table, env-var
fallback details, and "why this gate exists" evidence trail.

## Anti-patterns

| Pattern | Why bad | What to do instead |
|---|---|---|
| Move every-invocation detail to `references/` | agent doesn't load references at decision time | keep in main file |
| Pure prose compression that breaks critical path | constraint vanishes; behavior changes silently | preserve gate tables, never/always bullets |
| `scripts/` containing only one-line wrappers | overhead with no benefit | inline in SKILL.md until ≥ 5 lines or repeated |
| Main file > 500 lines | reader skim past gates | split detail to `references/`, link from main |
| `references/` file > 600 words | bloat; reader bounces | split or compress to working-draft (~300 words) |

## Override

Rare. Orchestrator skills (e.g. `flow-dev`) may need longer main files
to keep all routing visible at one glance. Declare the override in the skill's
**SKILL.md frontmatter** — `standard-override: disclosure-rule-5` — which is
where `standards-gate.md` step 2 consumes it; record a human-readable
justification (e.g. `disclosure-rule-5 (orchestrator needs inline routing)`)
in `INDEX.md` as an audit note.

## Validation

Disclosure cross-cuts. A2 Behavior catches critical path leaked to
`references/` (skill misbehaves under load). `prose-guidelines` audit (DEV static advisory)
measures main-file paragraph compression. Manual reviewer checks
main-file line budget against Rule 5.
