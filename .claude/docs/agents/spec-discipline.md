> ⚠️ This doc is now superseded by the model-invoked skill `spec-discipline/SKILL.md`. Retained as source reference.

# Spec discipline

When writing a new spec that changes or extends existing behavior:

## Three cases

| Situation | Action |
|-----------|--------|
| Bug found in current spec (error / ambiguity) | Edit the spec file directly. Commit as `fix(spec): <slug> — <reason>`. No new file. |
| New spec **supersedes** existing spec behavior | New spec gets `supersedes:` frontmatter → old spec gets `> ⚠️ DEPRECATED` notice. Commit both together. |
| New spec **extends** existing spec (no conflict) | New spec gets `depends-on:` frontmatter only. Old spec untouched. |

## Frontmatter convention

New spec that supersedes an old one:
```yaml
---
supersedes: docs/spec/YYYY-MM-DD-<old-slug>-design.md
reason: <one-line why>
---
```

Old spec — prepend this block immediately after any existing frontmatter:
```markdown
> ⚠️ DEPRECATED — superseded by [`docs/spec/YYYY-MM-DD-<new-slug>-design.md`](../spec/YYYY-MM-DD-<new-slug>-design.md)
```

New spec that depends on an old one:
```yaml
---
depends-on: docs/spec/YYYY-MM-DD-<prerequisite-slug>-design.md
---
```

## What NOT to do

- Do not create a new spec and leave the old spec unmodified when behavior is superseded — agents reading the old spec will follow the wrong path.
- Do not delete old specs — git blame and decision history live there.
- Do not use an ADR for spec-level behavior changes — ADRs record architecture decisions, not spec content evolution.
