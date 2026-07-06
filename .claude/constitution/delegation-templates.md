# Delegation Prompt Templates

Fill-in templates for the five common dispatch shapes. Each implements the
delegation triad from [model-dispatch.md](model-dispatch.md) Rule 2: goal+motivation,
acceptance criteria, report format. Copy the block, fill the brackets, don't
freehand a new prompt structure per task — consistency here is what makes future
sessions' dispatches predictable to read and to audit.

## Search / locate

```
Goal: find [WHAT] because [WHY THIS MATTERS — what decision depends on the answer].
Context: [what you already know/ruled out, so the agent doesn't redo it].
Search: [specific patterns/tools to try — grep terms, directories, naming variants].
Acceptance criteria: report is done when [every match found and confirmed real, OR
  a specific negative result confirmed — "searched X, Y, Z, none contain it"].
Report format: file:line table, one row per hit. No prose summary unless asked.
  Flag anything ambiguous (partial match, stale-looking) rather than silently
  including or excluding it.
```

Dispatch to: `Explore` (quick/medium/thorough per breadth — state which).

## Implement

```
Goal: implement [WHAT] so that [WHY — the behavior change this enables, and for
  whom].
Context: [relevant files, existing patterns to follow, constraints already known].
Acceptance criteria: [checkable condition — "X passes", "calling Y with Z returns W",
  not "implement X well"]. State explicitly if tests must be written vs already
  exist.
Non-goals: [what NOT to touch/refactor/add — prevents scope creep into adjacent code].
Report format: file:line for each change, one line each. State whether acceptance
  criteria were verified (ran it) or only reasoned about (and if so, why not run).
```

Dispatch to: `general-purpose` or a project-specific dev agent. Isolation: `worktree`
if this runs concurrently with other file-mutating dispatches.

## Refactor

```
Goal: refactor [WHAT] to [END STATE], preserving [WHAT MUST NOT CHANGE — behavior,
  public API, output format].
Context: [why now — what's driving the refactor, so the agent can judge edge cases
  the same way you would].
Acceptance criteria: behavior-equivalence confirmed by [specific method — existing
  test suite passes, before/after diff on a fixed input set, manual invocation
  matching]. A refactor with no equivalence check is not done.
Report format: summary of what moved/renamed/merged, file:line list, and HOW
  equivalence was confirmed (not just "it should be equivalent").
```

Dispatch to: `general-purpose` agent, or the `code-simplifier` agent type for pure
clarity passes with no behavior change intended.

## Research

```
Question: [the specific question — narrow it before dispatching; "what should we do
  about X" is not researchable, "what are the tradeoffs of A vs B for X" is].
Why this matters: [decision this feeds].
Already known/ruled out: [save the agent from re-deriving your prior work].
Acceptance criteria: [what counts as a complete answer — e.g. "cite at least N
  independent sources" or "read the actual source code, not just docs, for claims
  about behavior"].
Report format: under [N] words. Claims get a citation (file:line, URL, or command
  output) — uncited claims are flagged as such, not presented as fact.
```

Dispatch to: `general-purpose`, `deep-research` skill for multi-source web research,
`Explore` for codebase-only research.

## Review

```
Scope: review [WHAT — a diff, a file, a PR, a design doc] for [DIMENSION(S) — bugs,
  security, prose density, architectural fit — name them, "review this" with no
  dimension invites generic pass].
Acceptance criteria: every finding is [CONFIRMED or PLAUSIBLE] — reviewer states
  which, per model-dispatch.md Rule 4 (verify != self-verify: a finding the reviewer
  itself flagged as uncertain should say so, not get rounded up to confirmed).
Report format: one line per finding, severity-tagged, `file:line: <severity>:
  <problem>. <fix>.` No praise, no restating what's already correct, no scope creep
  into dimensions not asked for.
```

Dispatch to: the `code-review` skill for code, a fresh-context `general-purpose`
agent for docs/decisions per model-dispatch.md's adversarial-review pattern.

## Filling these in: the one rule that applies to all five

If you can't fill in "acceptance criteria" with something checkable, stop and
sharpen the goal first — an uncheckable acceptance criterion guarantees premature
completion (judgment-rubric.md §2) no matter how good the dispatched agent is.
