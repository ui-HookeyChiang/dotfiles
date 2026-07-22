---
name: example-skill
description: An example skill with a live WIP note that has backing code under scripts/ — the judge must see the code reference and return keep, not consider-removing.
expected: NEGATIVE — kind=unbuilt judge returns keep because scripts/parallel-advisory.sh exists; must NOT flag
---

# Example Skill

## Parallel advisory (Phase 2 — in progress)

> **Note:** Phase 2 pending — `scripts/parallel-advisory.sh` is under active
> development. The single-threaded fallback in `scripts/advisory.sh` runs
> automatically when the parallel variant is not yet available on the host.

When Phase 2 completes, `--with-llm --top 5` will dispatch all five advisory
calls concurrently rather than sequentially. The implementation stub in
`scripts/parallel-advisory.sh` already handles argument parsing and the
concurrency harness; the LLM dispatch loop is wired but gated behind
`ADVISORY_PARALLEL=1`.
