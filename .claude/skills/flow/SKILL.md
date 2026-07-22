---
name: flow
description: >-
  Thin pipeline orchestrator that composes matt skills into the stage-model
  dev workflow. Each stage is a gen/adver pair — converge, spec, decompose,
  dev, fan-in, integration, build, deploy, e2e, done. Use when starting a
  new feature, implementing from a PRD, or running the full dev pipeline.
  Triggers on "start feature", "implement this PRD", "run the pipeline",
  "new task from spec". NOT for single-file fixes without a spec (use
  flow-dev directly until migration completes). NOT for non-code work.
argument-hint: "<feature-description|PRD-path>"
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

Produce a PRD from clarified intent.

- **Gen:** `Skill to-spec` — m=2 independent drafts (ungrounded: agent prose)
- **Adver:** `Skill adversarial-review` n=2 (spec-gating mode)
- **Gate:** independent Moderator synthesizes findings → gen fixes spec
- **Output:** spec published to configured tracker

### 3. Decompose

Split spec into independently-grabbable vertical slices.

- **Gen:** `Skill to-tickets` — produces issue files
- **Adver:** `Skill adversarial-review` n=1 (challenge split — lightweight)
- **Gate:** independent Moderator → gen fixes split if findings warrant
- **Output:** tickets on configured tracker (one per task)

### 4. Dev (per-task, parallel)

Implement each issue as a stacked branch.

- **Gen:** implement + `Skill tdd` (grounded: tests verify)
- **Adver (reading):** `Skill code-review` n=2 (attack diff)
- **Adver (execution):** tdd red-replay (scratch checkout)
- **Gate:** independent Moderator receives code-review findings → gen fixes → commit
- **Context:** issue body is full context (no HANDOFF.md)

For skill tasks:
- **Gen:** `Skill skill-writer`
- **Adver (reading):** `Skill skill-audit` n=1
- **Adver (execution):** `Skill verify-skill` (5 voters, APPROVE/REJECT)

#### Dev stage details

Sequence: implement → code-review → gen fix.

1. **Gen dispatch:** `implement` + `Skill tdd` produce code on stacked branch
2. **Adver dispatch:** `Skill code-review` n=2 as independent reviewers (parallel,
   background — per-task). Falls back to `Skill code-review` alone if
   `adversarial-review` is unavailable
3. **Independent Moderator:** fresh-context agent receives both reviewers' findings and
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

Real target, real deps, no mocks. A/B comparison against baseline.

- **Mechanism:** e2e test suite against deployed target
- **Gate:** pass/fail; regression = block
- **Skip:** skill repos → jump to done

### 10. Done

Squash-merge, cleanup, status updates.

- **Mechanism:**
  - `Skill flow-merge` — cascade merge + cleanup + status updates
- **Gate:** target branch green post-merge

## Loop: spec-discipline

When dev reveals a spec gap:

| Gap type | Path | Action |
|---|---|---|
| Bug in spec (wrong requirement) | edit-in-place | fix spec, re-decompose affected tasks |
| Replacement (obsoletes spec) | supersedes | new spec with `Supersedes:` header |
| Addition (new requirement) | extends | new ticket linking to original spec |

Trigger: `Skill spec-discipline` — auto-invoked when dev agent detects
requirement mismatch.

## Domain context injection

All adver dispatches include (per adversarial-review §2 context injection):

1. `CONTEXT.md` — project domain model, vocabulary
2. Relevant ADRs from `docs/adr/`
3. Codebase structure summary (top-level layout, module boundaries)
