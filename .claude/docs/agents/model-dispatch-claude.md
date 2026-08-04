# Model Dispatch

`model-dispatch/native.tsv` is the editable authority for tier -> model,
effort, and escalation. This file is the human-readable runtime guidance.
`model-dispatch/runtime-model-pins.tsv` records which runtime surfaces can
enforce those pins and where each descriptor lives.

| Agent | Criterion | Model × Effort | Escalation rule |
|-------|-----------|----------------|-----------------|
| `scan` | Bounded — input contains all needed info (grep, locate, classify, extract) | Haiku 4.5 low | verifier catches errors |
| `scan` search-flavored | Info NOT in input — multi-hop repo lookup | Sonnet 5 low | Haiku floors here (0.14 acc) — never route |
| `execute` | Goal clear, success verifiable (implement, test, deploy, build) | Haiku 4.5 low | verifier failure → Sonnet 5 low → Opus 4.8 low |
| `execute` review-shaped | Verdict on a diff/claim | Sonnet 5 low | Haiku only where false-REJECTs tolerable (errs strict, FA=0) |
| `execute` deep-diagnosis | Root-cause from inline evidence | Sonnet 5 low (Opus 4.6 value pick) | discovery-coupled → search binding |
| `decide` | Trade-off judgment, no single correct answer | Opus 4.6 medium (contexted decomposition) | unknown spec quality → Opus 4.8 low; contract-heavy → Fable 5 low |
| `fable` | One failed run costs more than the price delta | Fable 5 low | — |

Rules: effort stays low — "needs > medium → promote model, not effort"
(effort-inversion). Exception: when low-effort token budget physically
truncates multi-part structured output (e.g. opus-4.6 deep-v2: low out_tok
~130 finds 1/2 causes, medium ~800 finds 2/2 — Round 8 evidence), promote
effort to medium before promoting model. Decide tier promoted to medium:
Round 8 measured opus-4.6 low at 89% (32/36) vs medium at 100% (30/30) on
decide fixtures, at comparable cost ($0.15/pass vs $0.14/pass); deep-v2
showed the same pattern (low 14% vs medium 100%). Never give Haiku math,
multi-file long-horizon, or design generation. Bindings from local eval
rounds 1-8 (docs/ticket/2026-07-22-model-dispatch-eval-planner-executor.md);
Round 7 tested Opus 5 as an API challenger and did not displace Opus 4.6.
Round 8 validated decide binding (opus-4.6 medium 30/30 100%) and measured
effort sensitivity on deep-v2. 4.6 slots stay while API-active — rebind on
Anthropic 4.6 EOL notice.
model-eval provides evidence for binding decisions; it does not directly apply a row across different model ids, efforts, or dispatch surfaces.

## Runtime Enforcement

| Runtime | Enforcement |
|---------|-------------|
| Claude Code | Advisory only for model pins. Subagents inherit the main model; `SubagentStart` can inject escalation rules but cannot pin per-agent model. |
| OpenCode | Enforced through agent definition frontmatter installed from `docs/agent-definitions/*.md` to `~/.config/opencode/agents/*.md`, then registered in `opencode.json`. |
| Cursor | Enforced with a routing caveat through project descriptors generated from `docs/agent-definitions/*.md` to `.cursor/agents/*.md`. Cursor descriptors use Cursor model IDs from `cross-cli-dispatch/bindings.tsv`; `effort` is encoded in `model:` bracket parameters. Task routing still depends on subagent description matching or explicit invocation. |
| Codex | Capability gap placeholder. Keep native bindings as reference until Codex exposes per-agent model pins. |

## Runtime Agent Mapping

| Tier | Agent definition | Runtime binding |
|------|------------------|-----------------|
| `scan` | `docs/agent-definitions/scan.md` | `model: claude-haiku-4-5`, `effort: low` |
| `scan-search` | `docs/agent-definitions/scan-search.md` | `model: claude-sonnet-5`, `effort: low` |
| `execute` | `docs/agent-definitions/execute.md` | `model: claude-haiku-4-5`, `effort: low` |
| `execute-review` | `docs/agent-definitions/execute-review.md` | `model: claude-sonnet-5`, `effort: low` |
| `execute-deep` | `docs/agent-definitions/execute-deep.md` | `model: claude-sonnet-5`, `effort: low` |
| `decide` | `docs/agent-definitions/decide.md` | `model: claude-opus-4-6`, `effort: medium` |

`cross-cli-dispatch/agent-def-map.tsv` maps these tiers to agent definitions so
`cross-cli-dispatch/scripts/check-agent-defs.sh` rejects drift from
`model-dispatch/native.tsv`.

`model-dispatch/scripts/sync-cursor-agent-defs.py` generates Cursor descriptors
from mapped agent definitions plus Cursor rows in
`model-dispatch/runtime-model-pins.tsv`; `model-dispatch/scripts/validate-runtime-pins.py`
checks descriptor presence, Cursor model syntax, and runtime binding drift.

`fable` remains a native escalation-only tier (`decide` -> `fable` -> `user`).
It is not registered as an OpenCode or Cursor agent until runtime support for
`claude-fable-5` is confirmed on that runtime.

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
