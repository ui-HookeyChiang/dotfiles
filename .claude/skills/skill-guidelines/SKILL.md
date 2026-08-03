---
name: skill-guidelines
description: Write-time guide for what belongs in a SKILL.md body — the closed set of six good-classes and body-wide rules.
argument-hint: "<skill-authoring-context>"
disable-model-invocation: true
landing-group: workflow
---

# Skill Guidelines

A skill exists to wrangle determinism out of a stochastic system. **Predictability** — the agent taking the same _process_ every run, not producing the same output — is the root virtue; every lever below serves it.

**Bold terms** are defined in the GLOSSARY disclosed by `writing-great-skills`; look them up there for the full meaning.

For the shared vocabulary (invocation, information hierarchy, pruning, leading words, failure modes), load `writing-great-skills`. This skill extends that foundation with the closed-set body rules below.

## Body content: the six good-classes

A SKILL.md body is a closed set. Anything outside these six classes is what
an auditor would flag — keep it out at write time rather than purge it later.
Full descriptions and pre-emption rules: [`references/good-classes.md`](references/good-classes.md).

1. **Triggers / routing** — when to use, when NOT, how to pick a mode.
2. **Contracts** — inputs, outputs, exit codes, side-effects, ordering, invariants.
3. **Live-mechanism instructions** — steps the agent runs NOW (intent + script invocations).
4. **Preconditions / caveats** — guards, gotchas, boundary conditions.
5. **Disambiguation** — "X vs Y", which to pick, NOT-this-skill.
6. **Pointers** — to `references/`, `scripts/`, sibling skills.


## Body-wide rules

Cross-class design principles that apply regardless of which good-class a line belongs to:

- **Delegate reasoning, keep mechanism** — keep the full rule in
  [`references/good-classes.md`](references/good-classes.md#body-wide-rules);
  the body only points to that SSOT.

## Not this skill

- Auditing an existing skill's problems → `skill-audit`.
- Prose density / tightness → `prose-guidelines`.
- Code style / structure → `coding-guidelines`.
- Building/orchestrating the skill (the create/modify/rewrite flow) →
  `skill-writer` (which applies THIS guide at its write step).
