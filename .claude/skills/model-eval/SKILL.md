---
name: model-eval
description: Benchmark Claude models per dispatch tier (scanner/executor/planner) with pinned --model/--effort per run, deterministic scoring, and a one-JSON-line-per-run ledger. Use when the user asks to eval/benchmark models against each other, measure cost-per-pass or pass rate per model, test a dispatch-table binding (which model for scan/execute/plan), compare tokenizer inflation across models, or rerun the model-dispatch eval. NOT for skill evals (use skill-creator evals) and NOT for picking a model from published benchmarks alone (use research).
disable-model-invocation: true
argument-hint: <tier: scanner|executor|planner|tokenizer> [models…]
standards-applied: [description, contract, behavior, trigger-eval, disclosure]
---

# Model Eval

Benchmark Claude models per dispatch tier with the `claude` CLI. Every run is
one fresh headless invocation with a pinned model+effort; every run appends
one JSON line to a ledger. Baseline results 2026-07-22/23:
`docs/ticket/2026-07-22-model-dispatch-eval-planner-executor.md`.

## Preconditions

- `claude` CLI on PATH. The in-session Agent tool CANNOT pin model versions
  or effort — only the CLI can (`--model claude-opus-4-8 --effort low`).
- Set `MODEL_EVAL_OUT=<dir>` (default `./model-eval-out`); ledger appends to
  `$MODEL_EVAL_OUT/ledger.jsonl`.
- Headless runs load the user's CLAUDE.md routing: never use `--max-turns 1`
  for generation tasks — the model may burn turns on routing/tool attempts
  and return an EMPTY result. Runners here already set sane limits.
- n=3 default. Read `references/harness-pitfalls.md` BEFORE modifying any
  runner or adding a tier.

## Tiers

| Tier | Runner | Scoring | Pass criterion |
|---|---|---|---|
| scanner | `scripts/run-scanner.sh <model> <idx> [effort]` | ground-truth field accuracy (machine) | accuracy in ledger |
| executor | `scripts/run-executor.sh <model> <idx> [v1\|v2\|v3] [effort]` | test suite green + forbidden-file sha (machine) | `pass` in ledger |
| planner | `scripts/run-planner.sh <model> <idx> <context_file> [effort] [contexted\|no-context] [repo_dir]` | 8-item checklist (agent-scored) | ≥6/8, see `references/planner-checklist.md` |
| tokenizer | `scripts/run-tokenizer.sh <model> <zh\|en> <idx>` | out_tok on verbatim repeat = tokenizer size | comparative only |
| review | `scripts/run-review.sh <model> <idx> [effort] [blurb:on\|off]` | 6 diffs vs contract; accept-verdicts vs truth (machine) | `accuracy`, `false_accept` (the AFK-critical miss), blurb delta = persuasion cost |
| search | `scripts/run-search.sh <model> <idx> [effort] [repo_dir]` | multi-hop repo facts + 1 abstain probe (machine, substring) | `accuracy`, `abstain_ok`, `num_turns` |
| deep | `scripts/run-deep.sh <model> <idx> [effort]` | root-cause diagnosis, fixing forbidden (machine, keyword) | `causes_hit`, `wrongly_blames_wt_id`, `pass` |

Executor difficulty knobs and fixture-authoring rules (seeded bugs + golden +
marker assert): `references/fixture-design.md`.

Planner modes — contexted (context inlined, measures decomposition quality)
vs no-context (repo access, measures discovery + abstention):
`references/planner-modes.md`.

Review/search/deep measure failure modes WITHIN existing dispatch tiers
(review=execute-class, search=scan-with-info-not-in-input, deep) — they are
not new tiers; merge-vs-split rule:
`docs/ticket/2026-07-23-model-eval-missing-tiers.md`.

## Run protocol

1. Pick tier(s), models, n (default 3). **Decision-relevant cells only**:
   candidates = the tier's incumbent binding ± one adjacent model class
   (one down-probe, one up-bound). A cell whose outcome cannot change a
   binding is waste — a class two levels below the incumbent unlocks ONLY
   if the class directly below passes first (ladder, not full matrix). Run matrix in background; runners are
   sequential-safe.
2. Run indexes MUST be numeric-safe strings (ledger dedupe keys on them).
3. Executor: before trusting any batch, check `test_last` in the ledger shows
   the CURRENT fixture's total (e.g. `pass=14` for v3) — a wrong-suite copy
   bug once produced a silently-invalid batch.
4. Aggregate: `python3 scripts/aggregate.py $MODEL_EVAL_OUT/ledger.jsonl`
   (dedupes reruns, last entry wins; computes pass, cost/pass, false-done).
5. Planner plans are scored by the orchestrating agent against
   `references/planner-checklist.md`; record scores next to the ledger.
6. **Archive**: binding-relevant rounds MUST be archived via
   `scripts/archive-round.sh <slug> [--filter <jq>]` before the decision
   PR merges. Evidence lands in `model-eval/evidence/`.

## Interpreting results

- Cross-round cost comparisons are cache-polluted (first run ~2x): compare
  out_tok/latency across rounds; cost only within a round.
- `false_done=true` (claimed PASS, verifier says fail) is a first-class
  result, not noise — track its rate per model; it gates AFK viability.
- All-models-ceiling means the task lacks discrimination on pass rate: the
  verdict is then the COST axis, or raise difficulty via fixture knobs.
- Empty planner output = harness or compliance failure — investigate
  claude.json before scoring (do not score as 0 silently).

## Incremental runs (new model/effort combos)

The ledger is cumulative and `aggregate.py` dedupes on the capability cell key
(tier, q, model, lang, effort, run) — so testing a new combo NEVER requires
rerunning old cells.

1. **Check what exists first**: `python3 scripts/aggregate.py $MODEL_EVAL_OUT/ledger.jsonl`
   — any (tier, model) row already present with the wanted effort is done; skip it.
2. **Run only the new cells**: same runner, new model id / effort arg, n=3.
   Example prompt to the agent: "用 model-eval 測 <model> [<effort>] 在
   <tier>，已有數據的組合跳過" — the agent runs step 1, diffs the wanted
   matrix against existing rows, and runs only the missing ones.
3. **Effort is part of the cell key**: same model at a different effort is a
   NEW cell and aggregates separately, so effort variants share one
   MODEL_EVAL_OUT dir and one run-index range. Indexes stay numeric.
4. **Cost caveat**: the new cells are cache-cold; compare them to old cells
   on out_tok/latency, not cost (pitfall #3).

## Evidence axes

Three independent axes; keep them in separate records.

- **Capability** — `ledger.jsonl`, cell key (tier, q, model, lang, effort, run).
  The key excludes `backend` on purpose: capability evidence for an identical
  model id transfers across channels, so an api run and a subscription-CLI run
  of the same model accumulate in one cell. api-vs-sub is NOT a scoring axis.
  `backend` (from `MODEL_EVAL_CLI`, default `claude`) and `tier` (from `TIER`,
  omitted when unset) ride along as metadata only.
- **Harness** — `harness.jsonl` via `scripts/append-harness.py`
  (env: `OUT`, `MODEL`, `RC`, `LAT`). "Can this channel run at all" is a
  (backend, model) fact, read back keyed on that pair. Separate file so the
  capability key never grows a backend dimension. No aggregator yet.
- **Quota** — `cross-cli-dispatch/scripts/quota-estimator.py`, not here.

Rows written before 2026-07-27 have no effort/tier/backend and are NOT
migrated; `aggregate.py` defaults them at read time, so they aggregate as
effort/tier-unknown cells and print without the `effort=`/`tier=` decoration.

## Not this skill

- Deciding which model to bind in the dispatch docs → that judgment stays
  with the user/ticket; this skill only produces the evidence.
- Published-benchmark research → `research` / `deep-research`.
- Skill trigger evals → `skill-creator` eval tooling.
