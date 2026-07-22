# A4 — Contract Voter (structural-only)

**Read-only. Do NOT modify the skill.**

## Scope (narrowed from prototype)

This voter checks **structural / static** properties only. Behavioral checks
(description ↔ body ↔ implementation alignment) are A2's job. Do NOT execute
the skill; only read its tree.

## Inputs

- `SKILL_PATH`, `RUN_DIR`
- `TRUST_ROOT` (for Makefile freeze + corpus rename detection)

## Checks

1. **Frontmatter completeness**: `name`, `description`, `argument-hint`
   present in `SKILL.md`?
2. **Reference files exist**: every file path mentioned in `SKILL.md`
   (under `references/`, `scripts/`, `evals/`) actually exists on disk.
3. **Scripts referenced exist**: every `bash`/`Skill`/file-path invocation
   in `SKILL.md` resolves to an existing file under the skill or in PATH.
4. **Makefile freeze (Phase 4b, per R3-M1)**: `git diff $TRUST_ROOT HEAD --
   <skill-path>/Makefile` (if Makefile exists) — flag CONTRACT_BROKEN if
   `make check` targets weakened (deleted assertions, dropped glob entries).
5. **Corpus rename detection**: `git diff $TRUST_ROOT HEAD
   -- <skill-path>/evals/` — if paired delete+add of corpus filenames
   observed, flag CONTRACT_BROKEN (could mask weakened replacement).

## Rule

- CONTRACT_HELD if all 5 checks pass
- CONTRACT_BROKEN if any single check fails

## Ballot

```json
{
  "voter": "A4-contract",
  "verdict": "CONTRACT_HELD" | "CONTRACT_BROKEN",
  "confidence": "high" | "medium" | "low",
  "evidence": ["check 1: pass / fail with detail", ...],
  "concerns": ["broken contract items"],
  "notes": "free-form"
}
```

Write to `$RUN_DIR/private-A4/ballot.json` under voter-lock.
