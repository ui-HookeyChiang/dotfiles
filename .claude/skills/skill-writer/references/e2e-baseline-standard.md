# E2E Baseline Standard

Owns the `rewrite` mode AB measurement protocol. Mandatory INTENT · E2E baseline A-capture for
any v1 → v2 rewrite; no `--skip-e2e-baseline` escape hatch.

## Rules

1. **Mandatory for `rewrite` mode.** INTENT · E2E baseline A-capture runs before
   any v2 design work. `--skip-e2e-baseline` is not a valid flag; if you think
   you need it, the change is `modify` or `improve`, not `rewrite`.
2. **Five measurement dimensions:** (a) trigger accuracy (true-pos %
   on a held-out set), (b) compliance under pressure (Adversarial cave
   count), (c) token cost per invocation (output tokens), (d) time to
   completion (wall clock), (e) loophole count (fresh Adversarial-
   discovery rationalizations).
3. **Snapshot v1** to `docs/dogfoods/<skill-name>-vN/iteration-M/v1-snapshot/`
   (cumulative iteration numbering — see `docs/dogfoods/README.md`).
4. **Spawn Agent Baseline in isolated worktree.** Agent Baseline MUST NOT see
   the v2 design (anchoring would invalidate the baseline). Pass only
   the v1 snapshot path + the 5 dimensions.
5. **After v2 implementation**, spawn fresh Agent REFACTOR-CHECK to
   run the same 5 dimensions on v2. User compares the two reports;
   **auto-PASS is forbidden** — the user must explicitly accept.
6. **INTENT · E2E baseline A-capture ≠ INTENT · audit-v1 ≠ TEST · resident dogfood — none substitutes for another.**
   INTENT · E2E baseline A-capture is a *live, comparative* 5-dim measurement (v1 vs v2 — "did it get
   better"). INTENT · audit-v1 is a *static read* of v1 ("what to fix") and does
   NOT satisfy the E2E baseline. TEST · resident dogfood is a *live, absolute* run of v2
   ("does it work now") and does NOT satisfy the E2E baseline either. Comparative and
   absolute are orthogonal axes; a `rewrite` owes all three. Reusing a prior
   round's verified v2 as this round's v1 baseline ("after-N → before-N+1") is
   forbidden: the v1 snapshot is always taken from the `origin/main` trust root
   (Rule 3), never from a self-authored prior round — chaining a self-graded
   "after" into the next "before" moves the bar off the trust root (the darwin
   `results.tsv` self-scoring hazard; see CONTEXT.md `_Avoid_` darwin).
7. **Navigability dimension — count, don't score (structural rewrites).** When the
   rewrite is a phase/stage REORG, navigability is the load-bearing dimension and
   is measured by two `rg`-countable proxies, not an LLM rating:
   (a) **top-level ID count** — `## ` stage/phase headings + sub-letters a reader
   must hold to know the flow; (b) **per-mode lookup-site count** — how many
   non-adjacent places state "rewrite only / modify skips" (or is there ONE
   unified map?). Report the integers ("ID count 23→3, per-mode lookup 14→1"), not
   the adjective. Anti-self-grade: A-side and B-side counted by DIFFERENT agents,
   the B-side agent forbidden to read any v1 number. A restatement that EXPLICITLY
   points at the SSOT ("per the Mode table") is NOT a drift site; only an
   independent restatement of the value counts.

## Examples

Measurement table (filled in per iteration):

| Dimension | Unit | v1 | v2 | Δ |
|---|---|---|---|---|
| trigger accuracy | true-pos % on held-out | 72% | 88% | +16 |
| compliance under pressure | cave count / 4 scenarios | 2 | 0 | -2 |
| token cost | output tokens / invocation | 4800 | 2100 | -2700 |
| time to completion | wall clock seconds | 95 | 60 | -35 |
| loophole count | fresh A5 rationalizations | 3 | 0 | -3 |

## Anti-patterns

| Pattern | Why bad | What to do instead |
|---|---|---|
| Agent Baseline reads v2 design | anchoring; baseline meaningless | pass v1 snapshot path only; no v2 context |
| < 3 dimensions measured | partial signal; v2 may regress on hidden axis | run all 5; do not abbreviate |
| Auto-PASS without user review | user is the floor on subjective dimensions | print comparison; require explicit accept |
| Reusing iteration-M for retry | overwrites prior evidence | increment to iteration-M+1 (script auto-detects) |
| Snapshot from working tree instead of trust root | drift between snapshot and actual v1 | snapshot from `origin/main` HEAD |

## Override

Trivial single-line rewrites can declare `modify` instead of `rewrite`
to skip INTENT · E2E baseline A-capture legitimately. The mode boundary is described in
[`equivalence-criteria.md`](equivalence-criteria.md): if the change is
local optimization with skeleton unchanged, it is `improve`; if the
skeleton changes (stage/phase reorganization, description change), it is
`rewrite` and INTENT · E2E baseline A-capture is mandatory.

## Validation

`scripts/dispatch-e2e-baseline-agent.sh` enforces the snapshot directory
structure and prints the Agent Baseline dispatch prompt. A3 Equivalence
voter checks that the declared mode matches the actual change (per
Rule 2 of equivalence-criteria); a `rewrite` declaration with no INTENT · E2E baseline
artifacts in `docs/dogfoods/` routes to NEEDS_HUMAN.
