---
name: skill-writer
description: Use when creating, modifying, refactoring, or rewriting any skill in this repo. Use even for small SKILL.md edits, single-file skill changes, or "just adding a section" — never invoke skill-creator directly. Use for v1→v2 rewrites. To AUDIT a skill (bloat, duplication, dead code, rubric score), route to skill-audit or darwin-skill — do not use skill-writer.
argument-hint: "[rewrite] <skill-description>"
test-devices: local
landing-group: workflow
standards-applied: [description, contract, behavior, disclosure, adversarial, equivalence, trigger-eval-design, e2e-baseline]
standard-override: [disclosure-rule-5, "behavior-rule-4 (orchestrator: one consolidated Important Rules section, each rule tagged to its stage)"]
---

# Skill Writer

Orchestrates skill creation, modification, and rewrites: dedup sweep → 8-standards gate → 5-voter quality gate. Always use instead of `skill-creator` directly.

## Writing or Auditing? (route first)

Skill-domain tier (counterpart to `coding-guidelines` for code, `prose-guidelines` for prose). Two modes — decide first:

- **Auditing** (bloat, duplication, dead code, rubric score) → **read-only, STOP.** Dispatch to engine below.
- **Writing** (create / modify / rewrite) → build path: three stages below.

`rewrite` may open with Auditing pass (feed v1 findings into v2) — recommended, not required. Stage mechanics: [`references/stage-mechanics.md`](references/stage-mechanics.md).

### Audit dispatch (read-only mode — STOP after)

Holistic "what's wrong" → `skill-audit` (read-side counterpart to `code-review`); returns one report.

| Intent | Engine | Invocation |
|---|---|---|
| holistic / "audit this skill" / problems + smells / one report | `skill-audit` | `python3 ~/.claude/skills/skill-audit/scripts/skill-audit.py <skill>` |
| bloat / 冗余 / scriptifiable / size-imbalance-staleness | `skill-audit` (deterministic leg) | `bash ~/.claude/skills/skill-audit/scripts/run.sh <skill>` |
| cross-skill duplication / overlap / consistency | `skill-audit` (probabilistic leg) | `bash ~/.claude/skills/skill-audit/scripts/syntax_audit.sh <skill>/SKILL.md` |
| dead code / unreachable script / orphan function / unused JSON field | `skill-audit` (deterministic leg) | `bash ~/.claude/skills/skill-audit/scripts/run.sh <skill>` |
| 9-dim rubric / single 0-100 score | `darwin-skill` | `Skill darwin-skill <skill>` |

All read-only (exit-code: `0` flagged / `1` error / `2` clean). Build-time advisory (DEV + TEST) runs skill-audit/prose-guidelines *during* a build. `skill-audit` covers all legs with `assert_audit_complete` trace.

## Flow + Mode (one map)

Build path = **three stages** (ADR 0004):

```
User → INTENT → DEV → TEST
       (pre-      (author +    (verify v2:
        authoring)  green +      LLM-review ∥
                    static       real-exec legs)
                    advisory)
```

**No BUILD stage**: skill has no fan-in artifact; `make check` = DEV green; *using* a skill IS building it (ADR 0004).

SSOT for per-mode behavior:

| Stage / step | create | modify | rewrite |
|---|---|---|---|
| **INTENT** · dedup sweep | ✅ | ✅ | ✅ (no exceptions, all modes) |
| **INTENT** · audit-v1 (condition-gated) | skip (no prior) | run if `scripts/` OR >200 ln; else skip | run (always qualifies) |
| **INTENT** · E2E baseline A-capture | skip | skip | **MANDATORY** (no `--skip-e2e-baseline`) |
| **DEV** · standards-gate | ✅ | ✅ | ✅ (+ equivalence + e2e-baseline refs) |
| **DEV** · content-placement scan | skip | skip | ✅ (+ pre-authoring assert) |
| **DEV** · skill-creator | new dir | modify existing | modify existing |
| **DEV** · `make check` (lint+test green) | ✅ HARD STOP | ✅ HARD STOP | ✅ HARD STOP |
| **DEV** · static advisory + eval-write | ✅ | ✅ | ✅ (+ references scan) |
| **TEST** · LLM-review (verify-skill) | effect | equivalence (OPTIONAL†) | effect |
| **TEST** · dogfood depth | smoke | smoke (OPTIONAL†) | **behavior** |
| **TEST** · e2e-AB-compare | skip | skip | ✅ (consumes INTENT baseline) |
| **TEST** · 5a trigger-eval live | run if desc changed | skip if desc frozen | run if desc changed |
| **TEST** · 5b skill-flow-execution | optional | optional | optional |

† **modify TEST optional** — skip unless desc changed, user requests, or >30% structural. `make check` green = binding gate.

Verify-skill: APPROVE → done / NEEDS_HUMAN → block / REJECT → back to DEV.

**Mode inference**: `rewrite` = user-declared (E2E baseline runs before v2). `create`/`modify` inferred: `create` when dir absent, `modify` when exists.

> **GUARD — missing target.** Modify/refactor verb + absent dir = typo, NOT create. STOP with `skill not found: <slug>`. Only `create`/`make`/`add` verbs may infer `create` on absent dir.

**Boundary**: `modify` = local optimization → equivalence; `rewrite` = structural → effect. Safety net: `modify` but >30% change → A3 NEEDS_HUMAN. `improve` = `modify`.

## Stage mechanics

Authoring principles → `skill-guidelines`. Stage-specific mechanics (borrow-vocab filter, two modes): [`references/stage-mechanics.md`](references/stage-mechanics.md).

## Stage 1 — INTENT

Pre-authoring: confirm what to build, assess v1. Three steps (per Mode table).

### dedup sweep (all modes, no exceptions)

> **GUARD — no description.** Request must carry usable description (DOES + triggers). Bare request → STOP, ask user. Do NOT forward empty description to skill-creator.

**Deterministic pre-pass** (invoke-cycle graph + lexical overlap; recommends whether Explore needed):

```bash
python3 skill-writer/scripts/dedup-prefilter.py --request "<description>" \
  [--self <skill-being-modified>] [--invokes <comma-list, create mode>]
```

Act on its `recommendation`:
- **`NO_OVERLAP_LLM_SKIPPABLE`** (top lexical < threshold, candidate not in a cycle) → the sweep would add little; note the brief and proceed to DEV **without** the Explore agent. (`preexisting_cycles`, if any, are an advisory repo-hygiene note — not this request's concern.)
- **`LLM_CONFIRM_SHORTLIST`** → launch the Explore agent below scoped to the brief's `shortlist` (the high-overlap skills) — it confirms true paraphrase / partial-overlap on those, not all 40+ skills.
- **`CIRCULAR`** → the candidate (`--self`/`--invokes`) sits in an invoke cycle; handle per the CIRCULAR verdict below regardless of overlap.

Pre-pass is advisory; LLM owns semantic dup judgment. Explore agent template: [references/explore-agent-template.md](references/explore-agent-template.md).

Act on the sweep verdict:
- **DUPLICATE** → recommend existing skill; ask if user wants to improve it.
- **PARTIAL OVERLAP** → propose (a) extend or (b) create new with clear boundary; recommend (a) unless audiences genuinely differ.
- **REFACTOR OPPORTUNITY** → extract shared logic to `_shared/`.
- **CIRCULAR** → **warn the user** with the cycle path (A→B→A); a skill-invocation cycle risks infinite delegation. Ask the user to break it (invert one dependency, or extract the shared step to `_shared/`) before proceeding.
- **NO OVERLAP** → proceed to DEV.

Do NOT skip — 30 seconds prevents sprawl.

### audit-v1 (rewrite / qualifying modify, condition-gated, advisory)

Audits **existing** v1 BEFORE authoring (informs rewrite). DEV advisory later reads v2 — before/after pair, not duplicate.

**Trigger** (condition-gated, auto-run): prior version exists AND (`scripts/` OR >200 lines). Skips: `skip-no-prior` / `skip-under-threshold` / `skip-audit-flag`.

**Runs** (read-only): `skill-audit` deterministic leg + `prose-guidelines` (no `--apply`). Findings collected verbatim → advisory input for skill-creator.

> **NOT darwin** — never in-flow (self-scoring hazard). Standalone post-merge only.

Uses `gate=advisory:<tool>` skip-trace convention. Detail: `references/phase-4-tools.md`.

### E2E baseline A-capture (rewrite only, MANDATORY)

Capture v1 failure baseline BEFORE v2 — the A-side for TEST's e2e-AB comparison. Live 5-dimension measurement, NOT TDD red test, NOT static audit-v1 (orthogonal axes).

```bash
bash skill-writer/scripts/dispatch-e2e-baseline-agent.sh <skill-path>
```

Snapshots v1 into `docs/dogfoods/<skill>-vN/iteration-M/v1-snapshot/`. Spawn Agent Baseline in isolated worktree; **must NOT see v2** (anchoring invalidates). A-side frozen here — TEST consumes by reference. Protocol: `references/e2e-baseline-standard.md`.

> **INTENT constraints (rewrite)**: no `--skip-e2e-baseline`; auto-PASS forbidden; the user reviews the 5-dim AB report at TEST, not here.

## Stage 2 — DEV

Author the skill, run all **deterministic** checks. No execution here — that's TEST.

### standards-gate (all modes)

Read `references/standards-gate.md` before skill-creator (8 standards table). Rewrite: also read `references/equivalence-criteria.md` + `references/e2e-baseline-standard.md`.

### good-class target (all modes — read before skill-creator)

Apply `skill-guidelines` (REQUIRED). Full good-class statements + audit-axis: `skill-guidelines`.

### content-placement scan (rewrite only)

Read-only Explore scan of SKILL.md + `references/` → **rebalance brief** (MIGRATE / SLIM / HOLD-IN-PLACE / DELEGATE). NEVER edits.

**Guardrail:** HOLD-IN-PLACE items (gate tables, NEVER/ALWAYS bullets, routing) MUST NOT migrate to `references/`. Contract: `references/content-placement-scan.md`.

**DELEGATE** — for each stage/phase/step in the body, if the inline reasoning
(how-to prose, multi-step workflow) overlaps with an existing skill's
description, emit DELEGATE: the reasoning belongs in the invoked skill, the
body keeps only (a) which skill to invoke, (b) what input to pass, (c) gate
condition after return. Detection: keyword-overlap between inline prose and
available skill descriptions (fuzzy, best-effort — false positives acceptable
since advisory). Ref: `skill-guidelines` body-wide rule "Delegate reasoning,
keep mechanism".

**Scan output.** After the scan agent returns, write the brief to `docs/dogfoods/<skill>/run-NNN/rebalance-brief.md`. Under `--skip-rebalance` the scan is skipped; `create` / `modify` skip entirely.

**Pre-authoring check (rewrite only).** Before invoking skill-creator, verify the scan ran — absent `run-NNN` evidence dir bounces back to this step. `create` / `modify` skip this check.

### skill-creator (author)

Invoke `skill-creator` with: request + INTENT findings + 8 standards + E2E Baseline (rewrite) + content-placement brief (rewrite). Honor HOLD-IN-PLACE guardrail. Modify: tell skill-creator to modify existing, not create new.

### agents/openai.yaml (agent harness sidecar, all modes)

After skill-creator returns, read the SKILL.md frontmatter and generate/update `<skill>/agents/openai.yaml`:

1. **Derive fields** — `display_name`: kebab-case `name` → Title Case. `short_description`: first sentence of `description`, strip leading "Use when"/"Use for"/"Use to", truncate to 80 chars with `…`.
2. **Invocation policy** — if frontmatter lacks `disable-model-invocation: true`, write `interface` block only; if `disable-model-invocation: true`, append `policy:\n  allow_implicit_invocation: false`.
3. **Modify gate** — skip regeneration if `name`, `description`, and `disable-model-invocation` are all unchanged from the prior version.

Use canonical vocabulary: "agent harness" (not runtime/platform), "invocation policy" (not access control/permission).

### make check (lint + scripts unit-test = green, HARD STOP)

Blocking gate. `make check` = `make lint` + `make test` (skill's `scripts/tests/*`).

| Check | Command |
|---|---|
| green | `make check` exits 0 |

**Non-zero → STOP.** Fix before advisory or TEST. Runs before probabilistic (fail-fast).

### static advisory + eval-write (advisory, all modes)

All advisory / non-blocking — read v2 statically. Binding gate = TEST. Detail: `references/phase-4-tools.md`.

| # | Tool | Trigger |
|---|---|---|
| `skill-audit` (deterministic) | static bloat metrics | has `scripts/` AND SKILL.md > 200 lines AND no `--skip-audit` (note: **AND**, narrower than INTENT audit-v1's `scripts/` **OR** >200 ln — v2 must be large enough to bloat-scan, whereas any prior v1 is worth auditing) |
| `prose-guidelines` (no `--apply`) | prose density | SKILL.md > 200 lines AND no `--skip-audit` |
| `quick_validate` | frontmatter parse | always (advisory; repo conventions win on field-allowlist false-rejects) |
| regression | re-read modified flows | always |

Both dispatch concurrently when triggered. Rewrite: also scan `references/*.md` (600-word trigger + HOLD-IN-PLACE leak check). `quick_validate`: repo-agreed checks only; PyYAML-absent → traced skip.

Static advisory NEVER edits, commits, or passes `--apply`.

**eval-write.** Update `evals/trigger-eval.json` to ≥ 16 cases (≥ 8 pos, ≥ 8 neg); `make lint` exits 0; commit alongside SKILL.md. **Anti-overfit**: designed by agent OTHER than description author.

## Stage 3 — TEST

> **Gating**: `rewrite` → MANDATORY. `create` → MANDATORY (dogfood=smoke). `modify` → OPTIONAL (skip unless desc changed, user requests, or >30% structural).

Two legs (never merge): **LLM-review** (read/score v2) and **real-execution** (run skill on task).

### LLM-review leg

**`skill-audit` probabilistic** (advisory) — semantic bloat audit deferred from DEV.

**verify-skill 5-voter (MANDATORY gate).** Delegated to `verify-skill`; skill-writer owns gate decision. Preflight:

```bash
bash skill-writer/scripts/check-verify-skill.sh   # non-zero → STOP, print stderr verbatim
```

```
Launch 1 agent (subagent_type: general-purpose):
  With env VERIFY_SKILL_INVOKED_BY=skill-writer set, run
    `Skill verify-skill <skill-path>`
  Do NOT pass `--mode` — TEST must let verify-skill auto-detect
  (per-mode mapping is in the Mode table above). Capture
  verdict.json + the rendered 5-ballot summary verbatim.
```

Task unavailable → prefix with `VERIFY_SKILL_INVOKED_BY=skill-writer` (detail: `references/phase-6-gate.md`).

| Outcome | Action |
|---|---|
| APPROVE / APPROVE_WITH_NOTES | Pass — print notes; report done |
| NEEDS_HUMAN | BLOCK soft — print 5 ballots; user resolves |
| REJECT | BLOCK hard — print 5 ballots; back to DEV |

Full exit-code table: `references/phase-6-gate.md`. Constraints SSOT: §Constraints.

### real-execution leg

**Resident dogfood (MANDATORY).** Runs skill on *live* task — absolute "does v2 work" axis. Evidence dir required before done.

**Depth**: `smoke`/`behavior` per Mode table. Rewrite may NOT skip (`run=0` forbidden).

```bash
bash skill-writer/scripts/dispatch-dogfood-agent.sh <skill-path> [--task <text>]
```

Preparer allocates `run-NNN`, prints dispatch prompt + `DOGFOOD_TARGET=<skill-name>`. Does NOT spawn; main agent dispatches. Evidence: `docs/dogfoods/<target>/run-NNN/`.

**Dogfood completion check (before done).** Verify `run-NNN` evidence dir exists after the preparer returns and the Behavior agent (if any) joined. `$DEPTH=behavior` for `rewrite`, `smoke` for `modify`. Missing evidence dir → bounce back.

**e2e-AB-compare (rewrite only).** Run v2 through same 5 dimensions as v1 baseline; present A-vs-B. Consumes INTENT-frozen A-side by reference (never re-captures). **auto-PASS forbidden** — user reviews. Protocol: `references/e2e-baseline-standard.md`.

**5a trigger-eval live (advisory).** Run corpus against live model to measure actual triggering. Never auto-PASS/block. Skip when description frozen:

```bash
base=$(git merge-base origin/main HEAD)
git diff "$base" HEAD -- <skill>/SKILL.md | grep -qE '^[-+]description:'
# exit 0 => description changed => RUN ; exit 1 => frozen => SKIP (verdict=skip-desc-frozen)
```

**Anti-self-grading**: output is measurement only, NEVER mutates description (SSOT: `references/trigger-eval-design.md`). Prepare with `bash skill-writer/scripts/dispatch-trigger-eval-agent.sh <skill-path> [--runs <N>]`. Skippable: `skip-no-skill-creator`/`skip-no-corpus`/`skip-no-auth`.

**5b skill-flow-execution (optional, advisory).** Run modified skill's full flow on target environment (device or local). Detects `test-devices` frontmatter to choose device-bound vs local agent. SKIP when infra unavailable — advisory, does not hard-block. Procedure: [`references/skill-flow-testing.md`](references/skill-flow-testing.md).

## Flow Complete

Summarize outcomes + gate verdict. Point to next action.

```
skill-writer: modify my-skill — APPROVE_WITH_NOTES (verify-skill)
Evidence: docs/dogfoods/my-skill/run-003/ (smoke)
Next: open PR via flow-dev.
```

## When to Use

| Scenario | Action |
|---|---|
| "Create a skill for X" | Full flow: INTENT(dedup) → DEV(create) → TEST(verify-skill) |
| "Improve / add feature to skill X" | INTENT(dedup + audit-v1) → DEV(modify) → done (TEST optional) |
| "Rewrite skill X (v1→v2)" | **INTENT(baseline MANDATORY)** → DEV → TEST(verify-skill effect + e2e-AB) |
| "Audit / is this script still used / score skill X" | Read-only — route to the *Audit dispatch* table above and STOP (no stages) |

## Important Rules

- **Route first** — audit verb = read-only (dispatch + STOP); build verb enters stages.
- **Always sweep first** — no exceptions.
- **audit-v1 advisory + condition-gated** — prior exists AND (scripts/ OR >200 ln); NEVER darwin.
- **E2E baseline mandatory for rewrite** — no skip; auto-PASS forbidden; A-side frozen at INTENT.
- **`make check` = hard STOP** — exit 0 before advisory or TEST.
- **verify-skill mandatory for create/rewrite** — 5-voter; never edits/commits/auto-retries; no `--mode`. Optional for modify.
- **Dogfood mandatory for create/rewrite** — trace required; rewrite may not skip. Optional for modify.
- **TEST legs never merge** — LLM-review ≠ real-execution; e2e-AB ≠ dogfood.

## See Also

- `coding-guidelines` (scripts code) + `prose-guidelines` (SKILL.md body prose)
- `references/stage-mechanics.md` — borrow-vocab filter + two modes (Writing / Auditing)
- `references/INDEX.md` — full directory map + conflict resolution
- `references/standards-gate.md` — DEV pre-flight checklist
- `docs/dogfoods/README.md` — dogfood cumulative-iteration convention
- ADR 0004 — the 3-stage INTENT/DEV/TEST model (why no BUILD)
- **Audit engines** — see *Audit dispatch* table above.
