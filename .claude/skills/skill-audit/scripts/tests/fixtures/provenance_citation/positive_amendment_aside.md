---
name: example-skill
description: An example skill containing an Amendment parenthetical aside (Amendment A8, v2.1 wire-up) that the B-prov detector should flag.
expected: POSITIVE — provenance_citation; Amendment A8 parenthetical aside; target_fully_inline unclear; LOW
---

# Example Skill

## Dogfood gate

Every skill-writer invocation runs the dogfood smoke test before emitting a
verdict. The gate writes a trace line to the run-NNN log and asserts it after
the smoke completes. (Amendment A8, v2.1 wire-up — added after the resident-dogfood
feature shipped in PR #637.)

The gate is enforced unconditionally; passing `--no-dogfood` is not supported.
