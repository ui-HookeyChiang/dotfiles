---
name: coding-guidelines
description: Anti-LLM-mistake guardrails (think before coding, simplicity first, surgical changes, goal-driven execution, fail fast at trust boundaries, deterministic before probabilistic, AND structural design decisions — whether to merge/unify/rewrite/split a unit, compose-don't-merge, a prior 'killed' verdict is a hypothesis, reversibility-weighted choices). Use BEFORE writing or editing any code — feature, bugfix, refactor — during code review, AND when committing to a structural direction — "should we merge X", "should we unify Y", "rewrite vs refactor", "evaluate this approach". Triggers on "coding principles", "guardrails", "anti-LLM", "architecture decision", "should we merge", or whenever you are about to implement. NOT for routine implementation choices (which name, which algorithm, whether to add a flag) and NOT for general technical questions. Apply them on every code edit even when not named.
standards-applied: [description, contract, behavior, adversarial, disclosure, trigger-eval]
argument-hint: "[principle: think|simplicity|surgical|goal-driven|fail-fast|deterministic|decompose|compose|reversibility|pre-mortem]"
landing-group: workflow
---

# Coding Guidelines

Ten guardrails that cut the coding and design-decision mistakes LLMs make most: assuming instead of asking, overbuilding, sprawling diffs, "looks done" without proof, unguarded boundary input, running a probabilistic check before a deterministic one, swallowing a big task whole instead of splitting it, merging units that only share an output shape instead of reifying that shape and composing, treating a reversible and an irreversible choice the same, and running a panel that only echoes its own framing. Source: [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md).

These bias toward caution over speed. For trivial tasks, use judgment — the point is to catch the expensive mistakes, not to ritualize the cheap ones.

## 1. Think Before Coding

**Don't assume. Surface tradeoffs.**

Before implementing:
- State assumptions. If uncertain, ask.
- Multiple interpretations → present them, don't pick silently.
- Simpler approach exists → say so. Push back when warranted.
- Something unclear → stop, name the confusion, ask.
- **Separate the layers first.** Decompose before asking "can technique X solve this?" — a technique fitting one layer may be irrelevant to another. Name the layers, then apply guardrails per-layer.
- **A prior decision is a hypothesis.** "We already decided / killed this" is evidence, not a verdict — re-testable when a new angle appears. Verify against the live artifact, not the memory of it.

Wrong assumption = wrong implementation. Asking costs one question.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No unrequested "flexibility" or "configurability".
- No error handling for impossible scenarios.
- 200 lines that could be 50 → rewrite.
- One reason to change per unit. Two jobs = speculative about one — split.

Test: would a senior engineer call this overcomplicated? If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

Editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor what isn't broken.
- Match existing style.
- Unrelated dead code → mention, don't delete.

Your changes create orphans:
- Remove imports/vars/functions YOUR changes orphaned.
- Don't remove pre-existing dead code unless asked.

Test: every changed line traces to the request. Unrelated edits hide the real change and widen blast radius.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Vague → verifiable:
- "Add validation" → "Write tests for invalid inputs, make them pass"
- "Fix the bug" → "Reproduce with a test, make it pass"
- "Refactor X" → "Tests pass before and after"

Multi-step → brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong criteria let you loop independently. Weak criteria ("make it work") let "looks done" pass for "is done".

## 5. Fail Fast at Trust Boundaries

**Guard externally-sourced input at the boundary. Return early.**

Input crossing a trust boundary — caller args, parsed file, network response, env var, user input — validate up front with early return/abort. Don't let unvalidated data travel deep where assumptions pile up.

Not contradicting §2: §5 guards data crossing a trust boundary; §2 forbids guarding unreachable internal states. Test: "did this value cross a trust boundary?"

## 6. Deterministic Before Probabilistic

**When several checks gate the same work, run deterministic ones first.**

Deterministic checks (lint, schema, type-check, `make check`, presence test) fail fast and shrink what the probabilistic stage (LLM judge, network call, human review) handles. Determinism is load-bearing — an expensive deterministic gate still precedes the LLM judge.

- **Closed concept needs no LLM.** Finitely enumerable (graph reachability, byte-identical dup, schema, path resolution) → deterministic check IS the answer.
- Don't spend an LLM pass on input a regex/schema/test could reject.
- Input absent/inapplicable → short-circuit (N/A / skip), don't spawn the judge.
- **Not-run ≠ no-problem.** A check that sometimes cannot run must return explicit **N/A ("not run")**, never silent empty `[]` — caller can't tell "clean" from "never checked".

Test: "could a script have rejected this before the expensive stage?" Yes → gate it first. (Detector design where deterministic = recall pre-filter for LLM is audit-specific: see [`skill-audit/design-notes.md`](../skill-audit/design-notes.md).)

## 7. Decompose, Then Compose

**Split big tasks into independently-verifiable parts, then recombine at a boundary.**

- **Partition along seams, not size.** Cut where parts share least state — each buildable, testable, reasoned-about alone. Every part needing every other = rename, not decomposition.
- **Each part carries its own success criterion** (§4) — *done* when its own check passes, before siblings exist.
- **Recombine at a defined boundary**, not by reaching into internals — the seam is a contract (§8 takes over).

Orthogonal to §8: §7 splits one thing (divide-and-conquer); §8 decides how separate units recombine.

Test: "can I build and verify each part without the others?" No = wrong seam.

## 8. Compose on Shape, Merge on Contract

**When N units must combine, first ask what they share — the *output shape* or the *algorithm*. Only-shape → compose at a boundary, internals stay separate. Same algorithm → merge into one unit.**

- **Reify the shared shape (BEFORE reaching for merge).** When ≥2 units produce identical output by different means AND a downstream handles them uniformly → give that output a *named abstraction* (type/interface) each unit emits. Describes what output *looks like* (fields the downstream needs), never how computed.
  - **Trigger smell**: `if source == X` ladder downstream = missing boundary type. Reify it.
  - **Boundary**: abstraction carries only what consumer needs. Leak a paradigm-private field → decay toward merge.
- **Don't merge what only shares a shape.** Shared base class = *container*, not *contract* — hides N behaviors behind one name. (Composition-over-inheritance / trait-bound satisfaction.)
- **Merge only on a REAL behavioral contract** (same operation, same argument meaning). Different paradigms → compose, don't merge.
- **Fake-interface test:** can a caller use the shared method WITHOUT knowing the concrete type? Needs `if type == X` → fake contract → you're on the compose side.

Example: deterministic script + LLM judge + prose checker share no algorithm, but all emit `Finding {severity, location, message}`. Reifying `Finding` = compose-on-shape. Folding into `BaseAuditor` with `if mode == "llm"` = merge-on-fake-contract.

Test: "does consumer need to know which unit produced this?" No = reify + compose. Yes (genuinely same operation) = merge.

## 9. Reversibility-Weighted Decisions

**Before committing to merge, delete, or migration, classify the door.**

- **Two-way door** — reversible in one PR, no data loss. Decide fast.
- **One-way door** — schema migration, public API, merged unit, deleted file with live consumers. Before committing: (a) adversarial check (at least one agent/reviewer tasked to refute), (b) write the concrete reversal path (steps + cost). No statable reversal = more one-way than you think.

Test: "can we undo in one PR without data loss?" No = slow down.

Bundled proposal (merge AND schema change) → classify each layer separately. Bundle = as irreversible as its most one-way layer — split so two-way parts ship fast.

## 10. Pre-Mortem a Multi-Agent Panel

**Before spawning ≥3 agents to decide, pre-mortem the panel design.**

A panel amplifies its framing — it does not challenge it. Stance-assigned lenses argue within the frame; the loudest voice dominates synthesis.

- Include ≥1 NO-stance lens and ≥1 frame-challenger.
- Weight synthesis by argument quality, not volume.

Test: "if this panel returns wrong, what's the failure mode?" Usually: shared frame. Add the missing outside lens.

## Comments & docstrings

A comment earns its place only when it adds what code can't say — the *why*, intent, non-obvious consequence, or contract.

- **Don't restate the code.** `# clamp to [0,1]` above `max(0, min(1, x))` is noise. Section banners above obvious code = restating structure; keep only when boundary isn't self-evident.
- **Redundant comment is worse than none.** Stale comment lies. The line you don't write can't rot.
- **Docstrings state the contract** — arguments, return, errors, value ranges, side effects. Not a signature restatement or body walkthrough.
- **Keep comments tight:** one idea per sentence, active verbs, specifics, no meta ("this function…"). Full sentences, not dropped-article fragments.

§3 still holds: don't rewrite comments your change didn't touch.

## Naming

Name the purpose, not position (`L1.5`), letter-order (`6d`), or mechanism (`rebalance`).

- Self-explanatory identifier = its own documentation; opaque handle = glossary debt (forces CONTEXT.md entry).
- Load-bearing across traces/grep → careful lockstep migration, not a reason to keep opacity.

**Counterpart:** `code-review` (read-side) — audits code against these guardrails.

## Working as intended when

Fewer unnecessary diff changes, fewer overcomplication rewrites, clarifying questions before implementation.
