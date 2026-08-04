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

## Independent Moderator + gen-fix pattern

Every stage's adver output goes through an **independent Moderator** (fresh-context
agent, per adversarial-review §3), then the gen agent receives moderated findings:

1. **Moderator** (fresh agent) — disposition table for each finding: accept/dismiss + reason
2. **HIGH findings CANNOT be dismissed** — downgrade with evidence or Moderator flags as must-fix
3. **Gen receives Moderator output** — fixes accepted findings, runs echo-chamber close:
   - Is consensus independent confirmation or correlated echo?
   - What are reviewers collectively blind to?
   - What structural bias does this analysis carry?
   - Which load-bearing input is owner-only?

The gen agent does NOT moderate its own review findings (D7 experiment: gen-as-Moderator
rubber-stamps all findings uncritically).

## Per-stage model×effort bindings

Flagship models only for gen and final gates; adver fan-out rides cheap
models — quality comes from independent count, not per-agent intelligence
(adversarial-review experiments). Tier semantics and the escalation ladder:
`docs/agents/model-dispatch-claude.md` (effort-inversion applies: needs >
medium → promote model, not effort). Bindings from local eval rounds 1-6
(`docs/ticket/2026-07-22-model-dispatch-model-effort-bindings.md`).

| Stage | Gen | Adver | Moderator |
|---|---|---|---|
| converge / spec | Opus 4.8 high | Sonnet 5 medium × n | Sonnet 5 medium |
| decompose | Sonnet 5 medium | Sonnet 5 low n=1 | Sonnet 5 low |
| dev (per task) | Sonnet 5 medium | red-replay/review Sonnet 5 medium | — |
| dev stuck (after 3-step methodology) | Opus 4.8 | — | — |
| fan-in / integration | — | Opus 4.8 medium | — |

## Pipeline stages

### 1. Converge

Scope raw input into a grounded problem statement. Classify the input, dispatch
the matching tool (`grill-with-docs` is the converger; `research`/`prototype`
feed it, then grill). The *Grounded?* column is the grounded/ungrounded table
above keyed to input shape — **make it** → Gen/Adver/Gate mechanics below;
**arrives** → skip the m=2 fan-out, jump to *Next*.

| Raw input shape        | Tool                                 | Grounded? | Next     |
|------------------------|--------------------------------------|-----------|----------|
| fuzzy intent / feature | `grill-with-docs`                    | make it   | spec     |
| missing facts          | `research` → then `grill-with-docs`  | make it   | spec     |
| unfelt design question | `prototype` → then `grill-with-docs` | make it   | spec     |
| issue pile (not yours) | `triage`                             | arrives   | decompose |
| something broken       | `diagnosing-bugs`                    | arrives   | dev (fix) |
| codebase drift         | `improve-codebase-architecture`      | re-enters | re-grill as idea |
| Spec already on tracker | —                                    | arrives   | decompose |

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

#### Dev stage details

Sequence: implement → code-review → gen fix.

1. **Gen dispatch:** `implement` + `Skill tdd` produce code on stacked branch
2. **Adver dispatch:** `Skill code-review` n=1 (background — per-task). Code-review
   internally runs multiple parallel review agents across dimensions
3. **Independent Moderator:** fresh-context agent receives reviewer findings and
   produces a disposition table (accept/dismiss + reason per finding)
4. **HIGH findings must be fixed** — cannot be dismissed; downgrade with evidence
   or fix the code
5. Gen receives Moderator output and commits fixes; adver re-runs on updated diff if findings were HIGH

### 5. Fan-in

Assemble N task branches into integration tree.

- **Mechanism:** `merge-train.sh`
- **Gate:** all task branches green; merge conflicts resolved
- **On conflict:** dev agent for owning task resolves; re-run affected tests

### 6. Integration

Cross-task tests before expensive build. Mocks permitted (test doubles for
external deps). Fail-fast — abort pipeline on red.

- **Mechanism:** full test suite on assembled tree
- **Gate:** all tests green
- **On red:** route failure to owning dev task → fix → re-fan-in

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

All adver dispatches include (per adversarial-review §2 context injection):

1. `CONTEXT.md` — project domain model, vocabulary
2. Relevant ADRs from `docs/adr/`
3. Codebase structure summary (top-level layout, module boundaries)
