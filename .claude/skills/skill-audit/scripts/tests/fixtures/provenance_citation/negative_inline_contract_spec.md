---
name: example-skill
description: An example skill with a (spec: docs/spec/archive/X.md) citation whose contract IS fully reproduced inline — keep-judge grades target_fully_inline=true, so this would be MED; marked clearly so the reviewer understands the grading intent.
expected: NEGATIVE-ish — syntactically matches B-prov pre-filter (spec: citation), but keep-judge returns target_fully_inline=true because the three exit codes are fully defined inline above the citation. A real detector would return MED not flag-for-removal; this fixture documents the keep-judge boundary.
---

# Example Skill

## Exit-code contract (inline)

| Code | Meaning |
|---|---|
| `0` | Findings present — skill flagged for review |
| `1` | Tool error — invalid path or unreadable file |
| `2` | Clean — no findings; success sentinel for CI |

Callers branch on these three values (spec: docs/spec/archive/2026-05-29-syntax-audit-doc-correctness-extension.md).
The table above is the complete contract; the spec carries no additional detail
not already inline here.
