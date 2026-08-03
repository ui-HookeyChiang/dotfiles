---
name: cross-cli-dispatch
description: Route a dispatch-tier subagent run to subscription CLI channels (cursor / codex / opencode) with the Anthropic API as fallback, or run any model headlessly through one normalized adapter. Use when dispatching scan/execute-tier work that could ride subscription quota instead of API billing, when a run needs a non-Anthropic model pinned (the Agent tool cannot), when a CLI returns a quota/rate-limit error and the run must fall back down the channel chain, or when model-eval needs the cli-adapter backend switch. NOT for choosing which tier a task belongs to (model-dispatch-claude.md + eval tickets own that), NOT for decide-tier work (stays Anthropic), NOT for load balancing.
argument-hint: <tier: scan|scan-search|execute|execute-review|execute-deep> | run --backend <cli>
standards-applied: [description, contract, behavior, trigger-eval, disclosure]
---

# Cross-CLI Dispatch

Two entries share one adapter. The caller's selection mode decides:

- Caller already knows backend + model (model-eval, a pinned non-Anthropic run)
  → **Entry A — Pinning**. Uses `run` only; optional `--tier` is ledger
  metadata, not a request for chain selection.
- Caller wants a dispatch tier routed to the cheapest working channel →
  **Entry B — Economics**, even when forcing a backend family: `--allow`
  filters the chain there, and only `next-channel` parses it. Chain selection,
  quota fallback, Anthropic API tail.

Both entries need §Preconditions. Ledger schema and backend normalization are
shared (Entry A owns them; Entry B's runs emit the same lines).

## Preconditions

- Backend binaries on PATH as needed: `claude`, `cursor-agent`, `codex`,
  `opencode`. Only the channel actually selected must be installed.
- Subscription CLIs do NOT load Claude's CLAUDE.md but may load their own
  rules files — prompts must be self-contained.
- opencode has no explicit bypass flag; observed (1.18.3, 2026-07-23) running
  shell tools headlessly without prompting — treat as bypass-by-default and
  confine opencode runs to throwaway `--cwd` dirs.

## Entry A — Pinning: run one named model headlessly

The Agent tool cannot pin a non-Anthropic model; `run` can. The caller supplies
backend, model, and effort — this entry never consults `bindings.tsv`,
`next-channel`, or quota state.

```
scripts/cli-adapter.sh run --backend <b> --model <m> --effort <e> --prompt <p> [--cwd <dir>] [--tier <tier>]
```

Prints ONE ledger JSON line to stdout. Exit codes follow the shared contract in
Entry B step 3; a pinning caller sees 0 (result), 1 (usage error or non-quota
failure), or 75 (quota/rate-limit — the channel is marked exhausted for today
even though this entry never reads that state). On 75 a pinning caller has no
next channel to fall to — the table's "rerun step 1" action is Entry B only.
Retry later or pick another backend.

model-eval runners reach these backends via its `MODEL_EVAL_CLI` switch; the
ledger schema is aggregate.py-compatible.

### Ledger line schema

Every `run` prints one JSON line: `ts` (run completion, ISO-8601 UTC, second
precision), `q` (tier), `run` (numeric-safe index,
`--run-idx`, default 1), `backend`, `model`, `effort`,
`result`, `num_turns`, `cost_usd`, `in_tok`, `out_tok`, `cache_create`,
`cache_read`, `latency_ms`, `api_ms`, `exit_code`, `quota_exhausted`,
`cost_estimated`, `run_dir`. `cost_estimated: true` = the CLI reported no
usage; `cost_usd` is backend-reported and may be null for these rows — the
adapter does not estimate pricing. Raw output persists in `run_dir` (`raw.out`,
`stderr.log`) for offline rescoring — never rerun for a scoring bug.

### Backend normalization (what the adapter hides)

| Backend | headless | effort spelling | bypass | result format |
|---|---|---|---|---|
| claude | `-p` | `--effort` | (session perms) | JSON |
| cursor | `-p` | model-name suffix `-low/-medium/-high` (skipped when the id is already suffixed; `--effort none` = no suffix) | `--force` | JSON |
| codex | `exec` | `-c model_reasoning_effort=<lvl>` | `--dangerously-bypass-approvals-and-sandbox` | JSONL events |
| opencode | `run` | `--variant <lvl>` | unverified | JSON |

JSON extraction uses `raw_decode` — all 7 pitfalls in
`model-eval/references/harness-pitfalls.md` apply to this adapter.

## Entry B — Economics: route a tier down the channel chain

Channel-selection layer under each dispatch tier's binding. `model-dispatch/native.tsv` holds
tier→model/effort and the escalation edges; tier-choice criteria and the
escalation narrative stay in `docs/agents/model-dispatch-claude.md`. This entry
picks WHICH channel (cli, model, effort) executes the run and falls back
deterministically when subscription quota runs out.

### Policy - native dispatch binds, bindings.tsv routes

`bindings.tsv`: one row per tier, chain = ordered `backend,model,effort`
channels, semicolon-separated. `scripts/validate-bindings.sh` is the edit-time
schema gate; it checks required tier rows, model ids against `inventory.tsv`,
unsupported-row actions, and Anthropic API tails. `.pre-commit-config.yaml` wires
that gate when `model-dispatch/native.tsv`, `bindings.tsv`, or `inventory.tsv` changes.

`model-dispatch/native.tsv` is the binding authority for native (Anthropic) dispatch -
tier→model,effort plus the escalation edge. `bindings.tsv` chains are the
cross-CLI economics layer on top; each chain's Anthropic API tail must agree
with `model-dispatch/native.tsv`, which the gate enforces. Change the model or effort for a
tier in `model-dispatch/native.tsv` first, then the tail.

`docs/agent-definitions/*.md` are the third surface bound to `model-dispatch/native.tsv`: the
Agent tool reads their `model`/`effort` frontmatter, so a def that disagrees
silently dispatches off-binding. `scripts/check-agent-defs.sh` cross-refs them
per tier, with the tier→file mapping in `agent-def-map.tsv` (tiers without a def
today — execute-review, execute-deep, fable — are added as a row, not code).

Ordering and membership rules:

- A subscription channel enters a chain ONLY with cross-cli-matrix eval
  evidence passing both hard gates: pass-rate >= incumbent AND false-done = 0
  (`docs/ticket/2026-07-23-model-eval-cross-cli-matrix.md`).
- Same-model channels keep capability and harness evidence separate: if a
  subscription channel runs the exact Anthropic model id already bound in
  `model-dispatch/native.tsv`, capability evidence transfers; only harness smoke for that
  backend/model is needed before chain entry.
- Channels sort by API-equivalent $ saved; the Anthropic API incumbent is
  always the chain tail (metered; quota-marking is not backend-scoped, but in
  practice the API is metered and not subject to daily quotas).
- Empty chain = incumbent-only row — the valid initial state.
- No round-robin, no static daily caps, no balance polling. Determinism keeps
  eval and production comparable. Single-channel starvation, if ever observed,
  is an n=1 ticket (cheap upgrade: daily chain-head rotation).

### Dispatch flow

1. Select channel:
   `scripts/cli-adapter.sh next-channel --tier <tier> [--allow <backends>]` →
   `backend<TAB>model<TAB>effort` — first channel with no `quota_exhausted`
   mark today whose backend is available. Availability defaults to
   `detect-channels` (binary present + credential file present, cached daily).
   `--allow` is an intent filter and overrides detection entirely, so callers can
   force subscription-only or API-only runs. Unknown tier → exit 2. Known tier
   with `unsupported` or no usable channel → exit 3 plus one-line JSON reason for
   the calling skill.
2. Run the selected channel via the Entry A `run` invocation
   (`--backend`/`--model`/`--effort` from step 1). Prints ONE ledger JSON line.
3. Exit-code contract:

   | exit | meaning | action |
   |---|---|---|
   | 0 | `next-channel` selected a channel, or `run` completed with non-empty result | consume result |
   | 1 | usage error or non-quota run failure (empty result, backend error) | do NOT mark quota; treat as run failure per tier's escalation rule |
   | 2 | (`next-channel` only) unknown tier | fix caller or binding name |
   | 3 | (`next-channel` only) known tier has no usable channel (`unsupported` or exhausted/filtered chain) | caller consumes JSON reason; `decide` with no Anthropic channel uses `surface_to_user` |
   | 75 | quota/rate-limit error; channel auto-marked exhausted for today | rerun step 1 — next-channel now skips it |

4. Repeat 1→3 until exit 0 or `next-channel` returns exit 3. Channel exhaustion
   never climbs the model escalation ladder; the calling skill decides whether to
   defer, retry later, re-tier, or surface to the user from the JSON action.

Quota state lives in `~/.local/state/cross-cli-dispatch/quota-YYYYMMDD`
(override: `CROSS_CLI_DISPATCH_STATE`); dated files self-reset daily.
Channel detection cache lives beside it as `channels-YYYYMMDD` and self-resets
with the same date boundary. Detection is a cheap local probe only — backend
binary on `PATH` plus credential file present; auth expiry is caught lazily by
`run` failures. Marking is error-driven ONLY — never pre-mark a channel.

### Quota pressure estimator

`scripts/quota-estimator.py --ledger <f>... [--format table|json]` turns ledger
history into a per-`(backend, model, effort)` daily pressure signal. Provider
caps are hidden, so it never claims an absolute quota — a `75` event is a
right-censored observation whose preceding successful runs are a LOWER bound
(`capacity_floor`) on that day's capacity.

| pressure | condition |
|---|---|
| `1.0` | quota event today on that exact key; channel reported unavailable |
| `runs_ok_today / p20(capacity_floor)` | prior quota days give history |
| `N/A` | no capacity history, or history only from days that observed zero capacity |

Scoping is by exact key: a quota on `cursor,composer-2.5,none` says nothing
about `cursor,composer-2.5,high`, and the estimator leaves the sibling
available. A day whose first record is already a quota event observed no
capacity at all, so it contributes no floor — that is unknown, not "capacity
zero".

Integration point — PROPOSED CONTRACT, NOT YET WIRED. Today the estimator is a
standalone report: nothing in `next-channel` or `run` calls it, and no caller
consumes `pressure`. The intended contract when it is wired is that the
estimator ADVISES step 1 of the dispatch flow rather than gating it —
`next-channel` keeps selecting on the error-driven quota state alone, so a
stale or missing ledger can never strand a working channel. Under that
contract a caller warns at `pressure >= 0.8`, skips at `>= 1.0`, warns on
`N/A`, and `--allow` overrides the advice entirely. Those thresholds are
unvalidated starting points, not measured ones.

Pressure is the only intended throttle input. `api_equivalent_usd` and
`usd_saved` (api-equivalent minus actual `cost_usd`) are reporting columns for
cost-comparison tables, never a throttle source. Both price every channel at
one flat Sonnet 5 rate, which overstates savings on the scan and execute tiers
that displace Haiku 4.5 — read them as an upper bound on displaced spend.

`latency_ms` is summed and shown as `ms/run`. It is the intended operational
proxy for CLIs that report no token counts, but nothing consumes it yet;
pressure is run-count based. Using it needs a per-model latency baseline the
ledger cannot yet supply.

Days bucket in UTC on each record's `ts`, so a report does not shift with the
reporting machine's local zone. Legacy records predating the `ts` field count
toward the `--date` day (default: today UTC) — conservative, but it collapses
their history into one day, so multi-day pressure needs `ts`-stamped runs.

## Why one file, not two

The two entries are separated by heading, not by file. Pinning consumers today:
1 (model-eval). One consumer cannot show where the boundary wants to be, so the
seam is hypothetical. At 2 pinning consumers the seam is real — that is the
split trigger. Until then a physical split costs a cross-file jump on every
shared concern (ledger schema, backend table, exit codes) and buys nothing.

## Not this skill

- WHICH tier a task belongs to, and why → `docs/agents/model-dispatch-claude.md`
  (criteria + escalation narrative) plus eval evidence (`model-eval`). The
  tier→model/effort binding itself lives in `model-dispatch/native.tsv`.
- Benchmarking channels → `model-eval` (it calls this adapter).
- decide-tier / fable-tier judgment work → stays Anthropic, Agent tool.
- Provider-mixed single runs, round-robin, quota budgeting → non-goals by
  design (see Entry B Policy).
