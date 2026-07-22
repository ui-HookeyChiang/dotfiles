---
name: spec-discipline
description: >-
  Manage spec lifecycle — edit-in-place for bugs, supersede for replacement,
  extend for additions. Use when fixing a spec, superseding an old spec with
  a new one, editing a PRD, finding a bug in a spec, or extending a spec.
  Triggers on "fix spec", "supersede", "edit PRD", "bug in spec",
  "extend spec", "spec gap", "spec needs update".
  NOT for creating new specs from scratch (use to-spec).
  NOT for routine spec authoring (use brainstorming → to-spec pipeline).
argument-hint: "<spec-path> [edit|supersede|extend]"
landing-group: workflow
---

# Spec Discipline

Model-invoked skill that enforces the three-case spec lifecycle gate.
Source: `docs/agents/spec-discipline.md`.

## When to trigger

This skill auto-triggers when an agent is about to modify, supersede, or
extend an existing spec/PRD. It gates the action through one of three paths.

## Three cases

| Situation | Action |
|-----------|--------|
| Bug found in current spec (error / ambiguity) | Edit the spec file directly. Commit as `fix(spec): <slug> — <reason>`. No new file. |
| New spec **supersedes** existing spec behavior | New spec gets `supersedes:` frontmatter → old spec gets `> ⚠️ DEPRECATED` notice. Commit both together. |
| New spec **extends** existing spec (no conflict) | New spec gets `depends-on:` frontmatter only. Old spec untouched. |

## Decision gate

Before modifying any file under `docs/spec/`, ask:

1. **Is this a bug fix?** (error, ambiguity, wrong statement in existing spec)
   → Edit in place. Commit: `fix(spec): <slug> — <reason>`.

2. **Does this replace existing behavior?** (new approach supersedes old)
   → Create new spec with `supersedes:` frontmatter.
   → Add deprecation notice to old spec.
   → Commit both together.

3. **Does this add new behavior without conflict?** (extension, new feature)
   → Create new spec with `depends-on:` frontmatter (if prerequisite exists).
   → Old spec untouched.

## Frontmatter conventions

New spec that supersedes:
```yaml
---
supersedes: docs/spec/YYYY-MM-DD-<old-slug>-design.md
reason: <one-line why>
---
```

Old spec deprecation notice (prepend after frontmatter):
```markdown
> ⚠️ DEPRECATED — superseded by [`docs/spec/YYYY-MM-DD-<new-slug>-design.md`](../spec/YYYY-MM-DD-<new-slug>-design.md)
```

New spec that depends on another:
```yaml
---
depends-on: docs/spec/YYYY-MM-DD-<prerequisite-slug>-design.md
---
```

## What NOT to do

- Do not create a new spec and leave the old spec unmodified when behavior is superseded — agents reading the old spec will follow the wrong path.
- Do not delete old specs — git blame and decision history live there.
- Do not use an ADR for spec-level behavior changes — ADRs record architecture decisions, not spec content evolution.

## Loop-back integration

When a bug fix during dev reveals a spec gap, this skill triggers the
loop-back: spec edit/supersede/extend → loop back to review → decompose → dev.
The orchestrator calls this skill; the skill does NOT call the orchestrator.
