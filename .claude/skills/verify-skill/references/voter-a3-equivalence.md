# A3 — Equivalence Voter (equivalence mode only)

**Read-only. Do NOT modify the skill.**

## Inputs

- `SKILL_PATH` (working tree)
- `BEFORE_REF` (= `$TRUST_ROOT`)
- `RUN_DIR`, `FROZEN_CORPUS`
- Behavior inputs from `$TEST_PROMPTS` (corpus same as A2)

## Mode gate

If main agent passed `MODE=effect`, write verdict `NOT_APPLICABLE` immediately
with `notes: "effect mode; no before-version to compare"` and exit.

## Task (equivalence mode)

For each input in `$TEST_PROMPTS`:
1. Run the skill against the BEFORE version (use `git show $TRUST_ROOT:<file>`
   to materialize prior SKILL.md / scripts). Capture output.
2. Run the skill against the AFTER version (working tree). Capture output.
3. Compare:
   - Same scope-refusal behavior?
   - Same output schema / field set?
   - Behavioral metrics within ±10% (e.g. findings count, compression ratio)?

## Rule

- EQUIVALENT if every input's after-output is semantically equivalent to
  before-output (within stated tolerance per input type)
- DIVERGED if any input shows behavioral change beyond tolerance

## Ballot

```json
{
  "voter": "A3-equivalence",
  "verdict": "EQUIVALENT" | "DIVERGED" | "NOT_APPLICABLE",
  "confidence": "high" | "medium" | "low",
  "evidence": ["input X: before=<>, after=<>, delta=<>"],
  "concerns": ["..."],
  "notes": "free-form"
}
```

Write to `$RUN_DIR/private-A3/ballot.json` under voter-lock.
