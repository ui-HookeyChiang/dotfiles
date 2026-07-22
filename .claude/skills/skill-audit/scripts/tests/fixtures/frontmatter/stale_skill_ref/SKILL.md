---
name: stale_skill_ref
description: Use when checking stale skill references.
argument-hint: <x>
landing-group: workflow
---

# stale_skill_ref

This skill mentions `Skill nonexistent-skill` (should fire).

Placeholders that must be skipped:
- `Skill foo` is a placeholder example
- `Skill <name>` is a template syntax
- `Skill XXX` is documentation TBD

Real skill mention: `Skill real-skill` (must NOT fire — exists in oracle).

Inside code fence (must NOT fire):

```bash
# This Skill in-fence-skill is inside a code block.
echo "Skill in-fence-skill"
```

Body with `<x>` example.
