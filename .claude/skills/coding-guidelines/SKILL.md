---
name: coding-guidelines
description: Anti-LLM-mistake guardrails for implementation work: think before coding, simplicity first, surgical changes, goal-driven execution, fail fast at trust boundaries, and deterministic checks before probabilistic ones. Use when the user asks for coding principles, guardrails, anti-LLM mistakes, disciplined implementation approach, or explicit review against these guardrails. NOT for ordinary implementation/refactor/bugfix requests, routine PR correctness review, routine implementation choices (which name, which algorithm, whether to add a flag), broad architecture decisions, or general technical questions.
standards-applied: [description, contract, behavior, adversarial, disclosure, trigger-eval]
landing-group: workflow
---

# Coding Guidelines

Six guardrails that cut the coding mistakes LLMs make most: assuming instead of asking, overbuilding, sprawling diffs, "looks done" without proof, unguarded boundary input, and running a probabilistic check before a deterministic one. Source: [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md).

These bias toward caution over speed. For trivial tasks, use judgment — the point is to catch the expensive mistakes, not to ritualize the cheap ones.

Before implementing non-trivial code changes, state the applicable principles in one line: `適用原則: §2, §4, §5`. Omit the line only when the trivial-task judgment above applies.

## 1. Think Before Coding

**Don't assume. Surface tradeoffs.**

Before implementing:
- State assumptions. If uncertain, ask.
- Multiple interpretations → present them, don't pick silently.
- Simpler approach exists → say so. Push back when warranted.
- Something unclear → stop, name the confusion, ask.

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

Test: "could a script have rejected this before the expensive stage?" Yes → gate it first. Detector design where deterministic = recall pre-filter for LLM is audit-specific to `skill-audit`.

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

**Counterpart:** [`code-review`](../code-review/SKILL.md) (read-side) — audits code against these guardrails.

## Working as intended when

Fewer unnecessary diff changes, fewer overcomplication rewrites, clarifying questions before implementation, and an observable `適用原則: ...` line before non-trivial code changes.
