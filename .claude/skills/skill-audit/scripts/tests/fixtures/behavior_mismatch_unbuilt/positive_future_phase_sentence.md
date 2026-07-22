---
name: example-skill
description: An example skill with a "Future Phase N will …" sentence that a fresh agent would treat as current behavior.
expected: POSITIVE — kind=unbuilt; Future Phase 0 sentence describes unimplemented refusal logic; consider-removing
---

# Example Skill

## Input validation

The skill accepts a path to any SKILL.md file. Relative paths are resolved
from the current working directory.

Future Phase 0 will refuse paths outside the repository root and emit
`exit 1` with a structured error message containing the resolved absolute path.
For now the skill silently accepts out-of-tree paths and proceeds.

Pass `--strict-path` to opt in to the stricter behaviour on the current
release.
