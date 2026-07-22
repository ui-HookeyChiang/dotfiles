# TEST · verify-skill 5-voter Quality Gate — details

Invocation contract, exit-code routing, and the empirical evidence for the
TEST · LLM-review leg's verify-skill gate (`## Why this gate exists`).

## Invocation contract

TEST · verify-skill 5-voter is mandatory, runs once per skill-writer invocation, after
DEV · eval-write. Verification is delegated to `verify-skill`
(peer skill); skill-writer owns only the gate decision.

Preflight: `bash skill-writer/scripts/check-verify-skill.sh` — on
non-zero exit, STOP and print stderr verbatim. User must install
verify-skill before re-entering skill-writer.

Dispatch:

```
Launch 1 agent (subagent_type: general-purpose):
  With env VERIFY_SKILL_INVOKED_BY=skill-writer set, run
    `Skill verify-skill <skill-path>`
  Do NOT pass `--mode <effect|equivalence>` — TEST · verify-skill must let
  verify-skill auto-detect. Capture verdict.json + 5-ballot
  rendered summary verbatim.
```

Without `VERIFY_SKILL_INVOKED_BY=skill-writer`, `auto-detect-mode.sh`
falls back to `pipeline_mode=standalone`, silently bypassing auto-
pipeline ceiling protections. Detectable post-hoc by inspecting
`pipeline_mode` in `verdict.json`.

Env-var fallback: when the Task tool is unavailable, the main agent
must prefix EVERY verify-skill shell call with `VERIFY_SKILL_INVOKED_BY=skill-writer`.

## Exit code routing

| verify-skill exit | skill-writer behavior |
|---|---|
| 0 + APPROVE | TEST PASS — flow complete |
| 0 + APPROVE_WITH_NOTES | TEST PASS — print notes inline; flow complete |
| 0 + NEEDS_HUMAN | TEST BLOCK (soft) — print all 5 ballots; user resolves |
| 1 + REJECT | TEST BLOCK (hard) — print all 5 ballots; back to DEV |
| 2 | TEST STOP — corpus / preflight error; not skill-writer's fault |
| 3 | TEST STOP — self-invocation guard (skill-writer must never grade verify-skill) |
| 4 | TEST STOP — bare-clone / symlinked-foreign / outside-worktree |
| 75 | TEST STOP-RETRY — transient (/tmp unwritable OR harness contract failure) |
| 76 | TEST STOP — trust root uncomputable; configure flow-dev.trunk-ref |

## Gate decision

| verdict | meaning | next action |
|---|---|---|
| APPROVE | all 5 voters PASS, no escalation triggered | flow complete |
| APPROVE_WITH_NOTES | all 5 PASS but ≥ 1 voter raised a note | print notes; flow complete |
| NEEDS_HUMAN | mixed verdict OR auto-pipeline ceiling hit | block; user reviews ballots and either fixes or accepts override |
| REJECT | ≥ 1 voter FAIL | block; back to DEV to revise |

**TEST · verify-skill NEVER auto-retries.** Retries are user-initiated.

## Auto-pipeline mode

TEST · verify-skill invocations from skill-writer are in `auto-pipeline-improve`
mode (or `auto-pipeline-create` for new skills). verify-skill prints
the `[PUA-ADVISORY]` banner and applies pipeline-mode ceilings: 5/5
PASS routes to NEEDS_HUMAN to force standalone re-verification before
merge. This is intentional — preventing a self-graded auto-PASS at
PR end.

## Why this gate exists

A single honest Scorer with mild self-declared pressure can give a wrong
PASS (1.0) on evidence that three independent Scorers unanimously rate FAIL
(~0.6). A single Scorer performing every spec-required discipline (leak
audit, scope narrowing, pressure declaration) still misses substantive
false-positive bugs.

**Conclusion:** A single Scorer is insufficient even when honest.
Multi-voter (verify-skill's 5-voter) is the **minimum viable gate**.

## Constraints

- TEST · verify-skill NEVER edits SKILL.md.
- TEST · verify-skill NEVER auto-commits or auto-pushes.
- TEST · verify-skill runs once per skill-writer invocation (no recursion).
- TEST · verify-skill MUST pass `VERIFY_SKILL_INVOKED_BY=skill-writer` to enforce
  auto-pipeline mode.
- TEST · verify-skill MUST NOT pass `--mode` to verify-skill (auto-detect only).
