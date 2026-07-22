---
name: example-skill
description: An example skill with a "deferred to a follow-up — doc-only for now" prose marker that describes behavior not yet implemented.
expected: POSITIVE — kind=unbuilt; deferred marker with no scripts/ counterpart; consider-removing
---

# Example Skill

## Batch mode

Pass `--rank-all <dir>` to rank every SKILL.md under a directory by composite
bloat score.

The `--rank-all` flag also accepts `--with-llm` to run the LLM advisory pass on
the top-N entries. Parallelising the advisory calls across the top-N is deferred
to a follow-up — doc-only for now; the current implementation calls each
advisory sequentially.

The `--top N` option (default 3) controls how many skills receive the LLM pass.
