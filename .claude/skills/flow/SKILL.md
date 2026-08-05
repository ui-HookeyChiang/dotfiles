---
name: flow
description: >-
  Thin pipeline orchestrator that composes the mattpocock engineering skills
  into the stage-model dev workflow. Each stage is a gen/adver pair —
  converge, spec, decompose, dev, fan-in, integration, build, deploy, e2e,
  done. Use when starting a new feature, implementing from a spec, or running
  the full dev pipeline. Triggers on "start feature", "implement this spec"
  (or "PRD"), "run the pipeline", "new task from spec". NOT for a single grounded task
  (bug+repro, clear scope, agent-ready ticket — use flow-dev direct entry).
  NOT for non-code work.
argument-hint: "<feature-description|spec-path>"
landing-group: workflow
---

# Stage-Orchestrator

Thin pipeline: 10 stages, each a gen/adver pair. No inline reasoning — delegate
to skills. No inline mechanism — reference scripts.

Design: `docs/spec/2026-06-26-stage-model-matt-atoms-evolution.md`

## Grounded/ungrounded decision table

Determines whether m=2 gen fan-out is needed before adver runs.

| Input source | Grounded? | m=2 gen? |
|---|---|---|
| Human-authored (user intent, bug report) | yes | skip |
| Constraint-backed (failing test, repro steps) | yes | skip |
| Adver feedback from prior loop | yes | skip |
| Mechanically verifiable (code + passing tests) | yes | skip |
| Grill-confirmed converge output (user gated each decision) | yes | skip |
| Single-agent prose (to-spec output, design doc) | no | **m=2 fan-out** |

Rule: if input is grounded, gen produces once. If ungrounded (single-agent prose
with no external validator), fan out m=2 independent gen drafts and merge before
adver runs.

## Skip logic

| Condition | Action |
|---|---|
| Spec already published to tracker matching task | skip converge |
| Skill repo (no build artifact — detect via absence of `Makefile`/`Dockerfile`/`package.json` build target) | skip build, deploy, e2e |

## Moderator dispatch condition

Moderator synthesis (per adversarial-review §3-5) runs ONLY where a stage's
adver produces **n≥2 independent raw finding streams** needing synthesis
(converge AFK m=2, spec adver n=2, dev code-review's internal fan-out).
Single n=1 adver output or an already-aggregated verdict (verify-skill's
5-voter APPROVE/REJECT, decompose's n=1 audit) skips the Moderator and goes
straight to gen-fix / gate — synthesizing an already-synthesized verdict adds
an agent for no signal. Where Moderator remains: "HIGH findings cannot be
dismissed" (adversarial-review §3) still holds.

## Per-stage model×effort bindings

Stage roles map to `model-dispatch/native.tsv` tiers — this table carries
tier names only; concrete model×effort is resolved from native.tsv at runtime.

| Stage | Gen | Adver | Moderator |
|---|---|---|---|
| converge / spec | `decide` | `execute-review` × n | `decide` |
| decompose | `execute-review` | `execute-review` n=1 | `execute-review` |
| dev (per task) | `execute-review` | red-replay/review `execute-review` | — |
| dev stuck (after 3-step methodology) | `decide` | — | — |
| fan-in / integration | — | `decide` | — |

Tier semantics, escalation ladder, and the effort-inversion rule:
`docs/agents/model-dispatch-claude.md`. Bindings from local eval rounds 1-8
(`docs/ticket/done/2026-07-22-model-dispatch-model-effort-bindings.md`).

## Pipeline stages

### 1. Converge

Scope raw input into a grounded problem statement. Classify the input, dispatch
the matching tool (`grill-with-docs` is the converger; `research`/`prototype`
feed it, then grill). Look up groundedness for the input shape in the
*Grounded/ungrounded decision table* above — ungrounded → Gen/Adver/Gate
mechanics below (m=2 fan-out); grounded → skip the m=2 fan-out, jump to *Next*.

| Raw input shape         | Tool                                  | Next              |
|--------------------------|----------------------------------------|-------------------|
| fuzzy intent / feature   | `grill-with-docs`                      | spec              |
| missing facts            | `research` → then `grill-with-docs`   | spec              |
| unfelt design question   | `prototype` → then `grill-with-docs`  | spec              |
| issue pile (not yours)   | `triage`                               | decompose         |
| something broken         | `diagnosing-bugs`                      | dev (fix)         |
| codebase drift           | `improve-codebase-architecture`        | re-grill as idea  |
| Spec already on tracker  | —                                       | decompose         |

Triage ONLY issues you didn't create — `to-tickets` output is already agent-ready.

- **Gen:** user (interactive) OR m=2 gen fan-out (AFK + vague input)
- **Adver:** `Skill grill-with-docs` n=1 (interactive) | grill prompt n=2 (AFK)
- **Gate:** user confirms clarified intent (interactive) | independent Moderator → gen fix (AFK)
- **Skip:** spec exists on tracker → jump to decompose
- **On bug-fix loop:** spec gap detected → `Skill spec-discipline` → loop to spec

#### Converge AFK mode

When AFK + vague input (ungrounded path from decision table):

1. Dispatch m=2 **independent** agents with `grill-with-docs` prompts (domain
   context + challenge intent + suggest alternatives — NOT generic adversarial-review)
2. Each agent receives: `CONTEXT.md`, codebase structure summary, user's raw input
3. Gen agent **synthesizes both outputs** (no separate Moderator agent) —
   surfaces consensus, flags divergences between the two grill agents
4. Output: clarified problem statement with divergence annotations

### 2. Spec

Produce a spec (PRD) from clarified intent.

- **Gen:** `Skill to-spec`. Grounded → single draft. AFK ungrounded → m=2
  independent draft agents, orchestrator merges before adver. Seam check
  (to-spec step 2): interactive → ask the user as written; AFK → record seam
  assumptions prominently in the spec for adver+Moderator to attack.
- **Adver:** `Skill adversarial-review` n=2 (spec-gating mode) — reviewers
  dispatched as `execute` agent type, model passed explicitly per bindings
- **Gate:** independent Moderator (`decide` agent type, explicit model)
  synthesizes findings → gen fixes spec
- **Output:** spec published to configured tracker

### 3. Decompose

Split spec into independently-grabbable vertical slices.

- **Gen:** `Skill to-tickets`
- **Adver:** `Skill adversarial-review` n=1 (challenge split — lightweight),
  `execute` agent type, explicit model
- **Gate:** independent Moderator (`decide` agent type) → gen fixes split if
  findings warrant
- **Output:** tickets on configured tracker (one per task)

### 4. Dev (per-task, parallel)

Implement each issue as a stacked branch.

- **Gen:** implement + `Skill tdd` (grounded: tests verify)
- **Adver (reading):** `Skill code-review` n=1 (attack diff)
- **Adver (execution):** tdd red-replay (scratch checkout)
- **Gate:** independent Moderator receives code-review findings → gen fixes → commit
- **Context:** issue body is full context (no HANDOFF.md)

#### Dispatch

All tasks run inside ONE background execute agent. Before dispatch, materialize or validate the Stage 4 handoff against `flow-dev/references/handoff-contract.json` using `flow-dev/scripts/validate-handoff-contract.sh <handoff.json>`. The prompt includes:

1. Ticket file path list + feature prefix
2. `Skill flow-dev` (dev-loop details defined by flow-dev/SKILL.md)
3. Completion-report requirements from the contract: `per_task_status`, `failed_tasks`, `tests_run`, and `completion_summary`
4. "Update harness task tracker if available" (conditional — cross-CLI compat)

Single agent = single-writer for lock/merge-train/A5. Issue body is full context
(fresh context, not fork — fork breaks reproducibility and can't pin model tier;
if dev needs conversation-only context, fix the ticket). No user gates inside the
dev loop — interactive and AFK use the same dispatch path.

For skill tasks:
- **Gen:** `Skill skill-writer`
- **Adver (reading):** `Skill skill-audit` n=1
- **Adver (execution):** `Skill verify-skill` (5 voters, APPROVE/REJECT)

flow-dev owns the per-task dev loop mechanics (implement → red-replay +
code-review → Moderator disposition → fix) as SSOT: `flow-dev/SKILL.md`
Step 3-5. This stage dispatches flow-dev and gates on its reported verdict —
no inline loop mechanics here.

### 5-6. Fan-in / Integration

Delegates to flow-dev's Feature Integration (`flow-dev/SKILL.md` § Feature
Integration, procedure in `flow-dev/references/integration-protocol.md`) —
merge-train assembly, integration tests, red handling (fix in the owning
task's worktree, re-run, push, rebase downstream — no pipeline abort) are all
owned there as SSOT.

- **Gate:** flow-dev's integration agent reports pass on the assembled tree

### 7. Build

Produce deployable artifact. Selected by repo markers.

- **Mechanism:** detected from repo (`Makefile`, `Dockerfile`, `package.json`)
- **Gate:** artifact produced without error
- **Skip:** skill repos (no build artifact) → jump to done

### 8. Deploy

Push artifact to target environment. Agent-first, CI fallback.

- **Mechanism:** deploy script or CI trigger (declared seam)
- **Gate:** deployment healthy (health check passes)
- **Skip:** skill repos → jump to done

### 9. E2E

Real target, real deps, no mocks. e2e suite = frozen expectations; gate pass/fail against deployed target; regression = block.

- **Mechanism:** e2e test suite against deployed target, judged against frozen expectations
- **Gate:** pass/fail; regression = block
- **Skip:** skill repos → jump to done

### 10. Done

Squash-merge, cleanup, status updates.

- **Mechanism:**
  - `Skill flow-merge` — cascade merge + cleanup + status updates
- **Gate:** target branch green post-merge

## Loop: spec-discipline

When dev reveals a spec gap or requirement mismatch, trigger
`Skill spec-discipline`; that skill owns the spec lifecycle cases and returns
the pipeline to review → decompose → dev.

## Domain context injection

All adver dispatches inject domain context per adversarial-review §Context
injection (reviewers only — D9).
