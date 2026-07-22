---
name: example-skill
description: An example skill containing a parenthetical per-spec-path citation that the B-prov detector should flag for human review.
expected: POSITIVE — provenance_citation; (per `docs/spec/archive/…`) parenthetical; target_fully_inline=false; LOW
---

# Example Skill

## Exit-code contract

The skill exits with code `0` when findings are present, `1` on tool error,
and `2` when the target is clean (per `docs/spec/archive/2026-05-29-syntax-audit-doc-correctness-extension.md`).

Callers must treat `exit 2` as a success sentinel, not an error. Downstream
CI scripts that branch on `$?` should use `[[ $rc -le 2 ]]` rather than
`[[ $rc -eq 0 ]]`.
