<!--
DRY-RUN SAMPLE — Pocock to-tickets conversion shape. NOT published to GitHub Issues.
Source spec: docs/spec/proposed/2026-06-02-ideal-dev-workflow-stage-model.md
Demonstrates how the spec's UNIMPLEMENTED stages would map onto a GitHub Issue
for the proposed → Pocock migration. The spec stays in proposed/ (forward-looking
blueprint, NOT superseded — only the #661 stage-vocab rename has landed so far).
The real flow would `gh issue create` this body with label `ready-for-agent`.
NO `gh issue create` was run.
-->

# Issue — Ideal dev-workflow stage model: implement the unmapped stages

## Problem

The repo's flow-dev workflow conflates several distinct verification concerns
and leaves others homeless (from the spec's §1 Problem):

- **No unified build stage.** Compile/build is scattered per-task inside one Dev
  agent's self-test plus a later QA agent — there is no single "all tasks merged
  → one build" fan-in point.
- **dogfood is detached.** The Smoke dogfood runs against a mktemp fixture (not a
  build artifact) and its verdict is only a log line the main agent greps itself,
  bypassing the independent reviewer; the disjoint-happy-path fixture cannot
  reproduce the conflict/cleanup bug-class it claims to guard.
- **integration is misnamed "end-to-end".** A *true* real-environment e2e stage
  (real device / A-B) has no home — prod-only failures are caught by nothing.
- **code-review and integration are fused.** The QA agent does both run-the-suite
  and read-the-diff in one role — different activities, different failure modes.

Only the #661 stage-vocab rename has landed; the structural model below is unbuilt.

## Tracer-bullet slices (unimplemented stages)

Each slice is an independently shippable tracer through the model:

1. **build as fan-in keystone** — introduce a single post-merge build stage with a
   pluggable backend (make | npm | cargo | …) that emits a hash-addressed artifact
   + provenance manifest. Artifact-less repos return the merged ref as a trivial
   artifact. `build` is an INTERFACE, never collapses into tdd:green.
2. **dogfood consumes the artifact by hash** — re-home dogfood to run on the build
   artifact (by hash, no mktemp fixture), graded by the independent reviewer not a
   main-agent self-grep.
3. **split code-review from integration** — separate the static total-diff review
   (logic/correctness + cross-task consistency + adversarial test strength) from
   the dynamic integration run, as two distinct gated stages.
4. **e2e (broad-stack) stage** — add a real-target stage with mandatory A-B
   (A = pre-frozen baseline snapshot, B = artifact-by-hash), runtime-skippable by
   pure-library repos with no real target.
5. **four-gate loop classifier** — implement the retry / loopback / exogenous /
   escalate-human exit router with a human-set max-loopback-depth cap and logged
   exit-selection evidence (Oracle Isolation: router ≠ its own gate's oracle).

## Acceptance

- The forward DAG (converge → … → [dogfood ∥ integration ∥ e2e]) is instantiable
  as one emitted workflow per iteration.
- Load-bearing invariant holds: dogfood / integration / e2e all consume the ONE
  build artifact BY HASH (no rebuild, no hand-rolled fixture).

## Label

`ready-for-agent`

---

### Conversion notes (meta — for the migration, not part of the issue)

- Spec §1 Problem → the issue Problem section (verbatim concerns, condensed).
- Spec §2 per-stage contract rows that are NOT yet built (build / re-homed dogfood
  / split code-review / e2e / four-gate router) → tracer-bullet slices.
- The #661 stage-vocab rename is the only landed part → called out as already-done
  so the issue scopes only the remainder.
- This shows the SHAPE. A real run would publish via `gh issue create` with the
  `ready-for-agent` label; the spec stays in proposed/ (not superseded).
