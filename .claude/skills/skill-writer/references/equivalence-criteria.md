# Equivalence Criteria

Owns the **v1 vs v2 equivalence determination**. Drives A3 Equivalence
voter's mode auto-detection (effect vs equivalence).

## Rules

1. **Equivalence-preserving changes:** prose compression, splitting body
   content to `references/`, adding `scripts/` wrappers — none of these
   change behavior IF the critical path stays intact. A3 verifies by
   running the v1 corpus against the v2 main file.
2. **Effect changes:** ANY edit to `description:`, ANY change to phase
   order, add/remove a phase, change a gate threshold, flip a `never X`
   to `sometimes X`. These require effect-mode verification (all 5
   voters re-evaluate from first principles).
3. **Borderline:** sub-step reorder (`5a` ↔ `5b`), error message
   rewording, splitting body to `references/` with new "see X" links in
   the main file. A3 auto-detects by computing diff + running trigger-
   eval comparison.
4. **Auto-test threshold:** run v1 `trigger-eval.json` against v2
   description. If `(true-pos + true-neg)` changes by ≤ 5% → equivalence
   mode; > 5% → effect mode.
5. **User cannot declare mode in `rewrite` mode.** verify-skill auto-
   detects (TEST · verify-skill contract: skill-writer MUST NOT pass `--mode`).
   Manual `--mode` declaration is reserved for standalone `modify` /
   `improve` invocations by a human.

## Examples

GOOD (clearly equivalence-preserving):

```
- prose-guidelines paragraph compression on the main file (DEV static advisory `--no-llm` advisory)
- Move 9-exit-code table from main to references/phase-6-gate.md,
  keep 3-class summary in main
- Add scripts/check-verify-skill.sh wrapper (no logic change)
```

BAD declarations (would route to NEEDS_HUMAN):

```
- "I just refactored the TEST verify-skill section" — but the description was also updated
  (description change = effect by Rule 2)
- "Sub-step reorder only" — but 5a now contains a new gate decision
  (gate threshold change = effect by Rule 2)
- "Pure prose compression" — but the `never auto-commit` line was
  rewritten as "avoid auto-commit when possible" (constraint relaxation
  = effect by Rule 2)
```

## Anti-patterns

| Pattern | Why bad | What to do instead |
|---|---|---|
| Declaring `modify` when description changed | description = highest-leverage field; A1 will catch | declare `rewrite` or accept effect-mode re-grading |
| Assuming sub-step reorder is always equivalence | sometimes encodes new gate ordering | let A3 auto-detect; do not pre-classify |
| Bypassing the 5% threshold with manual reasoning | A3 anti-self-grading is the floor | accept A3's auto-detection verdict |
| Treating `scripts/` additions as effect | adding a wrapper without changing flow ≠ effect | equivalence-preserving by Rule 1 |

## Override

None. Equivalence is **mechanical**, not subjective. If the diff +
trigger-eval comparison says effect, it is effect — regardless of
authorial intent.

## Validation

A3 Equivalence voter computes the diff, runs trigger-eval comparison,
and routes to effect vs equivalence mode. In `rewrite` mode, A3 also
loads [`e2e-baseline-standard.md`](e2e-baseline-standard.md) to run the
5-dimension AB test as additional evidence.
