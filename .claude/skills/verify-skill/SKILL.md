---
name: verify-skill
description: Use to verify a skill's behavior before merge — effect mode for new skills, equivalence mode for refactors. Runs 5 isolated voters and aggregates to APPROVE / APPROVE_WITH_NOTES / NEEDS_HUMAN / REJECT, with corpus-freeze anti-self-grading so authorial pressure cannot game the result. The mandatory skill-writer Phase 6 quality gate; also runs standalone for a pre-PR sanity check on a skill change.
argument-hint: "<skill-path> [--mode effect|equivalence] [--rerun-voter A<n> --reuse-run <run-id>]"
landing-group: workflow
---

# verify-skill

5 isolated voter sub-agents verify a skill's behavior.

## When to use

- skill-writer Phase 6 (mandatory, auto-invoked)
- Standalone pre-merge verification
- Pre-PR sanity check on behavior-preserving refactors

## When NOT to use

- Self-grading (exit 3)
- Bare clone / foreign-repo symlink (exit 4)
- Performance/cost regression (correctness-focused; future A6)

## Flow

1. **Preflight** — auto-detect mode (effect|equivalence) + pipeline_mode, compute trust root (merge-base), validate harness, check corpus.
2. **Freeze corpus** — extract trigger-eval.json / test-prompts.json / adversarial-cases.json from trust root into `$run_dir/frozen-corpus/`.
3. **Spawn voters** — parallel, only those not predetermined-N/A. Each reads frozen corpus, writes `private-A<n>/ballot.json` under mkdir-atomic lock. Predetermined voters get synthetic `NOT_APPLICABLE` ballot directly.
4. **Wait** — 120s deadline per voter; timeout → synthetic TIMEOUT_FAIL ballot.
5. **Aggregate** — `scripts/voting-harness.py aggregate <run-dir>` → verdict.json.
6. **Render** — `scripts/render-verdict.sh <run-dir>` prints summary + PUA-ADVISORY banner.

## Voters

| # | Role | Corpus | Verdict tokens |
|---|---|---|---|
| A1 | Trigger | `evals/trigger-eval.json` (required) | TRIGGER_PASS / TRIGGER_FAIL |
| A2 | Behavior | `test-prompts.json` (or `evals.json` surrogate; N/A if neither) | BEHAVIOR_PASS / BEHAVIOR_FAIL / NOT_APPLICABLE |
| A3 | Equivalence | git diff auto-generated | EQUIVALENT / DIVERGED / NOT_APPLICABLE |
| A4 | Contract | reads all skill files | CONTRACT_HELD / CONTRACT_BROKEN |
| A5 | Adversarial | `evals/adversarial-cases.json` (optional) | ROBUST / FRAGILE / NOT_APPLICABLE |

Voters are read-only: cannot modify skill or read other ballots (isolated `private-A<n>/` dirs).

### Predetermined-N/A skip-spawn

When `NOT_APPLICABLE` is predetermined by corpus-presence or mode, skip spawn — main agent writes synthetic ballot directly. Zero verdict effect (aggregation weights same). Trust-bearing voters (A1, A4, and A2/A5 *with corpus*) always spawn.

| Voter | Skip-spawn when | Why N/A is predetermined |
|---|---|---|
| A5 Adversarial | `evals/adversarial-cases.json` absent at trust root | A5 template returns NOT_APPLICABLE immediately on absent corpus — no surrogate path |
| A3 Equivalence | `mode == effect` | A3 returns NOT_APPLICABLE immediately in effect mode — no before-version to diff |

**A2 always spawns** (surrogate path). **A1/A4 always spawn** (trust-bearing). Synthetic ballots use same schema + lock as TIMEOUT_FAIL; indistinguishable downstream.

## Aggregation

Full table: `references/aggregation-rules.md`. Headline:

- 5/5 PASS (standalone equivalence) → APPROVE
- 5/5 PASS (auto-pipeline-improve) → NEEDS_HUMAN (corpus same-run authored)
- 5/5 PASS (auto-pipeline-create) → APPROVE_WITH_NOTES (new skill)
- 4/5 PASS → APPROVE_WITH_NOTES
- 3/5 PASS → NEEDS_HUMAN
- ≤2/5 PASS → REJECT
- HC-1: 5/5 PASS + any high-conf concern → ceiling APPROVE_WITH_NOTES
- HC-2: ≥2 high-conf FAIL → ceiling NEEDS_HUMAN

## Invocation

```bash
# Standalone
Skill verify-skill <skill-path>

# Auto-pipeline (from skill-writer Phase 6)
VERIFY_SKILL_INVOKED_BY=skill-writer Skill verify-skill <skill-path>

# Single-voter re-run after manual fix
Skill verify-skill <skill-path> --rerun-voter A4 --reuse-run <run-id>
```

## Exit codes

| Code | Outcome |
|---|---|
| 0 | APPROVE / APPROVE_WITH_NOTES / NEEDS_HUMAN (NEEDS_HUMAN is BLOCK at caller side) |
| 1 | REJECT |
| 2 | Preflight error (skill not found, corpus missing) |
| 3 | Self-invocation refused (SC9) |
| 4 | Bare clone / symlinked-foreign / outside-worktree (SC16) |
| 75 | /tmp unwritable OR harness contract failure |
| 76 | Trust root uncomputable |

## Anti-self-grading

Guarantees:
- Voter cannot write skill's scoring asset (path isolation)
- Equivalence mode: A1/A2/A5 read from trust root, NOT local HEAD
- Auto-pipeline-improve 5/5 PASS → NEEDS_HUMAN (corpus may be same-run edited)
- PUA-ADVISORY banner on every auto-pipeline run

## Limitations (honest)

- Self-invocation refusal: `cp -r`-bypassable, defends accidental case only
- Hash-pin / prompt-freeze deferred to v2
- Trust root assumes `origin/main` integrity (human-enforced via code review)
- Same LLM family → correlated bias residual
