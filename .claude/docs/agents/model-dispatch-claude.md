# Model Dispatch

| Agent | Criterion | Model × Effort | Escalation rule |
|-------|-----------|----------------|-----------------|
| `scan` | Bounded — input contains all needed info (grep, locate, classify, extract) | Haiku 4.5 low | verifier catches errors |
| `scan` search-flavored | Info NOT in input — multi-hop repo lookup | Sonnet 4.6/5 low | Haiku floors here (0.14 acc) — never route |
| `execute` | Goal clear, success verifiable (implement, test, deploy, build) | Haiku 4.5 low | verifier failure → Sonnet 5 low → Opus 4.8 low |
| `execute` review-shaped | Verdict on a diff/claim | Sonnet 5 low | Haiku only where false-REJECTs tolerable (errs strict, FA=0) |
| `execute` deep-diagnosis | Root-cause from inline evidence | Sonnet 5 low (Opus 4.6 value pick) | discovery-coupled → search binding |
| `decide` | Trade-off judgment, no single correct answer | Opus 4.6 low (contexted decomposition) | unknown spec quality → Opus 4.8 low; contract-heavy → Fable 5 low |
| `fable` | One failed run costs more than the price delta | Fable 5 low | — |

Rules: effort stays low — "needs > medium → promote model, not effort"
(effort-inversion). Never give Haiku math, multi-file long-horizon, or design
generation. Bindings from local eval rounds 1-6
(docs/ticket/2026-07-22-model-dispatch-eval-planner-executor.md); 4.6 slots
stay while API-active — rebind on Anthropic 4.6 EOL notice.

## Escalation

Subagent completes 3-step failure methodology before returning (enforced by SubagentStart hook):
switch approach → reframe with 3 hypotheses → full checklist. Cannot report failure before step 3.

Before escalating, judge the failure type: capability gap → escalate; context/tools gap → surface to user directly.
Execution failure vs decomposition failure: if the CONTRACT is wrong (scope/acceptance mis-specified), rewrite the contract — do NOT escalate to a stronger model on the same contract.

| Failed agent | Escalate to |
|-------------|-------------|
| `execute` | `decide` |
| `decide` | `fable` [low] |
| fable [low] | Surface to user |

## Delegation

Every dispatch: **goal+why**, **acceptance criteria** (checkable), **report format** (<200 words, file:line),
**allowed_files**, **must_preserve**, **forbidden_changes**, **rollback**.
Limits: max_parallel_workers 4, max_subagent_depth 1, max_retries_per_node 1.
Verify ≠ self-verify: code → run tests; judgment → fresh-context subagent argues other side.

## False-done guard (AFK)

Before accepting planner/executor output, run a deterministic artifact-exists
check (file present, tests actually ran) — never trust "done/green" claims
alone. 2 false-done events on record (Opus 4.8-med planner 1/3; Sonnet 4.6 zh
empty plan 1/2).
