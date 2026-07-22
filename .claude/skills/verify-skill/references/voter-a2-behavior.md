# A2 — Behavior Voter

**Read-only on the skill. Do NOT modify the skill being verified.**

## Inputs

- `SKILL_PATH`, `RUN_DIR`, `FROZEN_CORPUS` (per A1)
- `TEST_PROMPTS`: `$FROZEN_CORPUS/test-prompts.json` (≥ 3 prompts) **OR**
  `$FROZEN_CORPUS/evals/evals.json` as surrogate when `test-prompts.json`
  is absent and `evals.json` has ≥ 3 prompts (see "Surrogate mode" below).

## Task

Execute the skill on each prompt from `$TEST_PROMPTS` (or surrogate
source). For each prompt:
1. Compare actual output against the prompt's `expected` (or
   `expected_output`) field
2. Check: does the skill's behavior match what its SKILL.md documents
   (output schema, refusal rule, hand-off rules, validator guarantees)?
3. Verify **description-↔-body-↔-implementation alignment**.

## Rule

- BEHAVIOR_PASS if all prompts produce contract-compliant outputs
- BEHAVIOR_FAIL if any prompt violates contract (fabricated output,
  schema mismatch, refusal-rule bypass, description-body drift)
- NOT_APPLICABLE only via surrogate-mode exhaustion (see below)

## Surrogate mode (when test-prompts.json absent)

`test-prompts.json` is a darwin-era artifact. New skills authored via
`skill-writer` Phase 5 ship `evals/evals.json` (skill-creator schema)
but not necessarily `test-prompts.json`. When `test-prompts.json` is
absent at the frozen corpus path, A2 falls back as follows:

1. **Surrogate found**: if `$FROZEN_CORPUS/evals/evals.json` exists and
   contains ≥ 3 prompt entries with usable `prompt` + `expected_output`
   (or `expected_artifacts`) fields, use those as the test corpus.
   Confidence downgraded to **medium** (surrogate ≠ explicit test
   intent). Note in ballot `notes`: `"surrogate: evals.json (test-prompts.json absent)"`.

2. **No surrogate available**: if neither `test-prompts.json` nor a
   usable `evals.json` (≥ 3 prompts) exists, return
   `BEHAVIOR_NOT_APPLICABLE` with confidence `high` and concerns
   listing the absent corpora. **Do not** return `BEHAVIOR_FAIL` on
   procedural grounds — A2 grades behavior, not corpus hygiene.
   (Corpus hygiene is A4's contract scope.)

The surrogate-mode behavior is auto-pipeline-aware: when
`pipeline_mode=auto-pipeline-create`, the surrogate is expected
(new skill authored same-run), so confidence stays `medium`. Under
`standalone` mode, surrogate is unusual; downgrade to `low` and
flag `concerns: ["consider adding explicit test-prompts.json"]`.

## Ballot

```json
{
  "voter": "A2-behavior",
  "verdict": "BEHAVIOR_PASS" | "BEHAVIOR_FAIL" | "BEHAVIOR_NOT_APPLICABLE",
  "confidence": "high" | "medium" | "low",
  "evidence": ["per-prompt observation"],
  "concerns": ["..."],
  "notes": "free-form (cite 'surrogate: evals.json' if surrogate mode used)"
}
```

Write to `$RUN_DIR/private-A2/ballot.json` under voter-lock (see A1 template).
Filesystem allow-list and timeout rules identical to A1.
