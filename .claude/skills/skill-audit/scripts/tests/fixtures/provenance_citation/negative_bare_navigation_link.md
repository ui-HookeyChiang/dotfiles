---
name: example-skill
description: An example skill using a bare navigation link "see docs/spec/archive/X.md" — not a parenthetical citation; the B-prov pre-filter must NOT match.
expected: NEGATIVE — bare navigation link, no parenthetical wrapper; must NOT flag provenance_citation
---

# Example Skill

## Design rationale

The three-exit-code convention was chosen to give callers a clean sentinel for
"clean audit" without conflating it with tool error. See
docs/spec/archive/2026-05-29-syntax-audit-doc-correctness-extension.md for the
full design rationale and the rejected two-code alternative.

The `exit 2` sentinel is now part of the published contract and must not be
changed without a new spec.
