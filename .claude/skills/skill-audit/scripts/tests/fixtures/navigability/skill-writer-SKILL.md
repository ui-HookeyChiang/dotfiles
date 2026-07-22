---
name: skill-writer
description: Use when creating, modifying, refactoring, or rewriting any skill in this repo. Use even for small SKILL.md edits, single-file skill changes, or "just adding a section" — never invoke skill-creator directly. Use for v1→v2 rewrites that need baseline failure measurement. To AUDIT a skill instead of building it — bloat, cross-skill duplication, dead/unreachable code, "is this script still called", rubric scoring — this skill body-routes (read-only) — a holistic "what's wrong" ask to skill-audit (fans out to all engines, one report), an axis-specific ask to the matching engine; skill-audit and the engines (skill-deterministic-audit / skill-probabilistic-audit / darwin-skill) also trigger directly.
argument-hint: "[rewrite] <skill-description>"
test-devices: local
landing-group: workflow
standards-applied: [description, contract, behavior, disclosure, adversarial, equivalence, trigger-eval-design, e2e-baseline]
standard-override: disclosure-rule-5
---

# Skill Writer

Orchestrates skill creation, modification, and rewrites with a dedup sweep, an 8-standards SSOT gate, and a mandatory 5-voter quality gate. Always use this instead of invoking `skill-creator` directly in this repo.

## Writing or Auditing? (route first)

This skill is the skill-domain tier — the counterpart to `coding-guidelines` (code) and `prose-guidelines` (prose). It runs in one of two modes; decide before anything else:

- **Auditing / reading** an existing skill (bloat, cross-skill duplication, dead code, "is this script still called", rubric score) → **read-only, no build.** Dispatch to the matching engine below and **STOP — do NOT enter the stages.**
- **Writing** a skill (create / modify / rewrite verb, or an absent target) → the build path: the three stages below.

A `rewrite` *may* open with an Auditing pass (audit v1, feed findings into the v2 build) — a recommended input, not a required gate. Full rationale + the seven authoring principles: [`references/principles.md`](references/principles.md).

### Audit dispatch (read-only mode — STOP after)

A holistic "what's wrong with this skill" ask → `skill-audit` (the read-side counterpart to `code-review`); it fans out to all three engines by path and returns one report. A single-axis ask → the specific engine.

| Intent | Engine | Invocation |
|---|---|---|
| holistic / "audit this skill" / problems + smells / one report | `skill-audit` | `python3 ~/.claude/skills/skill-audit/scripts/skill-audit.py <skill>` |
| bloat / 冗余 / scriptifiable / size-imbalance-staleness | `skill-deterministic-audit` | `Skill skill-deterministic-audit <skill>` |
| cross-skill duplication / overlap / consistency | `skill-probabilistic-audit` | `Skill skill-probabilistic-audit <skill>` |
| dead code / unreachable script / orphan function / unused JSON field | `skill-deterministic-audit` | `bash ~/.claude/skills/skill-deterministic-audit/scripts/run.sh <skill>` |
| 9-dim rubric / single 0-100 score | `darwin-skill` | `Skill darwin-skill <skill>` |

Each engine is standalone and read-only (never edits / commits / builds); they share one exit-code contract (`0` flagged / `1` error / `2` clean). The build-time `--with-llm` advisory dispatch inside the flow (DEV static advisory + TEST LLM-review leg) is a different thing — that runs skill-deterministic-audit / prose-guidelines *during* a build. Note: holistic `skill-audit` now covers both LLM advisory legs (skill-probabilistic-audit syntax+semantic G1/G8 + prose-guidelines) with a completion gate (`assert_audit_complete` trace assert) — not only the build path. A bare `skill-audit` run names all not-yet-dispatched legs; the gate enforces dispatch before reporting complete.

## Flow + Mode (one map)

The build path is **three stages**, a faithful collapse of the repo's approved 8-stage ideal-dev-workflow (ADR 0004 + CONTEXT.md *skill-writer stage model*):

```
User → INTENT → DEV → TEST
       (pre-      (author +    (verify v2:
        authoring)  green +      LLM-review ∥
                    static       real-exec legs)
                    advisory)
```

There is **no BUILD stage**: a skill has no fan-in artifact (one SKILL.md, not N merged task branches) and no build-distinct-from-use — `make check` is DEV's green, and *using* a skill IS building it (the build happens in TEST's real-execution leg). Rationale: ADR 0004.

This single table is the SSOT for per-mode behavior — read it instead of hunting "rewrite only" notes through the body:

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
| **TEST** · LLM-review (verify-skill) | effect | equivalence | effect |
| **TEST** · dogfood depth | smoke | smoke | **behavior** |
| **TEST** · e2e-AB-compare | skip | skip | ✅ (consumes INTENT baseline) |
| **TEST** · 5a trigger-eval live | run if desc changed | skip if desc frozen | run if desc changed |

Verify-skill outcomes: APPROVE → done / NEEDS_HUMAN → block / REJECT → back to DEV.

**Mode inference**: only `rewrite` is **user-declared** (typed as the `[rewrite]` flag) — it MUST be typed because the E2E Baseline runs *before* v2 exists, so it cannot be auto-detected after the fact. `create` and `modify` are **inferred**, never typed: `create` when the target skill dir does not exist (`test ! -d <skill-path>`), `modify` when it exists and the skeleton is unchanged. This matches verify-skill's `auto-detect-mode.sh` (untracked dir → create).

> **GUARD — missing modify/refactor target (NEVER silently fall through to create).** When the request **names an existing skill to change** (verbs `modify` / `improve` / `refactor` / `rewrite` + a target slug) but `test ! -d <skill-path>` (the dir does not exist), this is a **typo or wrong slug, NOT a create**. STOP and surface `skill not found: <slug>` to the user before INTENT — do not infer `create` and do not reach TEST. Only a request with **no existing-target verb** (`create` / `make` / `add a skill for …`) may infer `create` on an absent dir.

**Mode boundary**: `modify` = local optimization (skeleton unchanged) → verify-skill equivalence; `rewrite` = structural rewrite (skeleton / stage reorganization / description change) → verify-skill effect. **Safety net**: inferred/declared `modify` but main file changes > 30% → Equivalence ballot (A3) routes to NEEDS_HUMAN. **Deprecated alias**: `improve` is a deprecated alias for `modify`.

## Principles (summary)

Seven authoring principles govern every build: lean SKILL.md, say-once, scriptify, description-is-trigger, no-history, mnemonic codes, deterministic-before-probabilistic — plus the retention guardrail (never cut a precondition/caveat/contract/NOT-clause to hit a line target) and the per-stage deletion-test. Full statements + which audit detector each maps to: [`references/principles.md`](references/principles.md).

## Stage 1 — INTENT

The pre-authoring stage: confirm what to build and how bad v1 is, before touching v2. Three independent steps (run per the Mode table above).

### dedup sweep (all modes, no exceptions)

> **GUARD — no usable description (ask before authoring).** Before the sweep, check the request carries a usable skill description (what the skill DOES + when it triggers). A bare request with no description (e.g. "make a new skill", "create a skill") is **not actionable** — STOP and ask the user for the description before dispatching the sweep or `skill-creator`. `argument-hint` declares `<skill-description>` required; this is its prose enforcement. Do NOT forward an empty/placeholder description to skill-creator.

**Deterministic pre-pass first** (narrows or skips the LLM sweep — it does the mechanical parts exactly: invoke-cycle graph + lexical overlap ranking, and recommends whether the Explore agent is needed):

```bash
python3 skill-writer/scripts/dedup-prefilter.py --request "<description>" \
  [--self <skill-being-modified>] [--invokes <comma-list, create mode>]
```

Act on its `recommendation`:
- **`NO_OVERLAP_LLM_SKIPPABLE`** (top lexical < threshold, candidate not in a cycle) → the sweep would add little; note the brief and proceed to DEV **without** the Explore agent. (`preexisting_cycles`, if any, are an advisory repo-hygiene note — not this request's concern.)
- **`LLM_CONFIRM_SHORTLIST`** → launch the Explore agent below scoped to the brief's `shortlist` (the high-overlap skills) — it confirms true paraphrase / partial-overlap on those, not all 40+ skills.
- **`CIRCULAR`** → the candidate (`--self`/`--invokes`) sits in an invoke cycle; handle per the CIRCULAR verdict below regardless of overlap.

The pre-pass is advisory input — the LLM still owns the semantic dup judgment. When it recommends the sweep, launch the Explore agent (scoped to the shortlist):

```
Launch 1 agent (subagent_type: Explore, thoroughness: very thorough):
  Skill request: <user's description>
  Prefilter shortlist (focus here): <brief.shortlist>
  1. List skills: ls */SKILL.md
  2. Compare each description to the request
  3. grep -l "<keywords>" */SKILL.md for keyword overlap
  4. Check _shared/ for existing utilities
  5. Check cross-skill flows in orchestrators (flow-dev etc.)
  6. When the change touches ≥ 2 SKILL.md: also flag paraphrased /
     cross-file duplication (the cross-skill "G1" signal), not just
     verbatim keyword overlap.
  7. Cross-reference cycle: the pre-pass already computed the candidate's
     cycle status exactly (`candidate_cycles` in the brief). Do NOT re-trace —
     instead, if a candidate cycle was reported, judge whether it is a real
     infinite-delegation risk (A delegates to B which delegates back) vs a
     benign prose reference (one names the other in docs). Report CIRCULAR only
     for the former.
  Report: DUPLICATE | PARTIAL OVERLAP | REFACTOR OPPORTUNITY | CIRCULAR | NO OVERLAP
  Cite the specific SKILL.md lines that overlap.
```

Act on the sweep verdict:
- **DUPLICATE** → recommend existing skill; ask if user wants to improve it.
- **PARTIAL OVERLAP** → propose (a) extend or (b) create new with clear boundary; recommend (a) unless audiences genuinely differ.
- **REFACTOR OPPORTUNITY** → extract shared logic to `_shared/`.
- **CIRCULAR** → **warn the user** with the cycle path (A→B→A); a skill-invocation cycle risks infinite delegation. Ask the user to break it (invert one dependency, or extract the shared step to `_shared/`) before proceeding.
- **NO OVERLAP** → proceed to DEV.

**Do NOT skip this step** — 30 seconds prevents skill sprawl.

### audit-v1 (rewrite / qualifying modify, condition-gated, advisory)

Audits the **existing** version of the target skill BEFORE authoring, so v1's findings inform the rewrite (what to delete / fix). This is the v1 "what to fix" read; the DEV static advisory later reads the v2 draft (the "did I fix it / stay clean" read) — a before/after pair, NOT a duplicate (different artifacts, different questions).

**Trigger** (condition-gated, NOT mode-keyed — auto-run, no checkpoint): runs when a **prior version exists** (`git cat-file -e "$(git merge-base origin/main HEAD):<skill>/SKILL.md"`) AND the skill **has `scripts/` OR SKILL.md > 200 lines**. Otherwise auto-skips (traced): `skip-no-prior` (create), `skip-under-threshold` (small script-less modify), `skip-audit-flag` (`--skip-audit`).

**What it runs (on the EXISTING version, read-only):** `skill-deterministic-audit` (reachability / orphan scripts / dead fields / bloat), `prose-guidelines` (prose density, no `--apply`) — each via its *Audit dispatch* command. Findings are **collected verbatim, never merged** and folded into the DEV skill-creator input as **advisory** design input — never an auto-mutator.

> **NOT darwin.** `darwin-skill` is **never** run in any build stage — running it in-flow re-triggers its `results.tsv` self-scoring hazard (CONTEXT.md `_Avoid_` darwin). A single darwin number, if wanted, is a standalone post-merge run.

It uses the SAME `gate=advisory:<tool>` skip-trace convention as DEV's static advisory — a skipped engine appends one bare line (`<tool>` ∈ `deterministic-audit` / `prose-guidelines`) to `.git/flow-dev-sandwich.log`. Skip-reason enumeration, the before/after rationale, and the collect-not-merge findings-flow: `references/phase-4-tools.md`.

### E2E baseline A-capture (rewrite only, MANDATORY)

For `rewrite` mode, capture the v1 failure baseline BEFORE designing v2 — the **comparative** A-side that TEST's e2e-AB leg compares v2 against. It is a live 5-dimension measurement, NOT a TDD red test, and NOT the static audit-v1 read above (three orthogonal axes — see CONTEXT.md *baseline*).

```bash
bash skill-writer/scripts/dispatch-e2e-baseline-agent.sh <skill-path>
```

The script snapshots v1 into `docs/dogfoods/<skill>-vN/iteration-M/v1-snapshot/` (cumulative numbering) and prints the Agent Baseline dispatch template. Spawn Agent Baseline in an isolated worktree; **Agent Baseline MUST NOT see the v2 design** (anchoring invalidates the baseline). The captured A-side is **frozen here** at the dev boundary — TEST's e2e-AB leg consumes it by reference, never re-captures. Full protocol + why-orthogonal derivation: `references/e2e-baseline-standard.md`.

> **INTENT constraints (rewrite)**: no `--skip-e2e-baseline`; auto-PASS forbidden; the user reviews the 5-dim AB report at TEST, not here.

## Stage 2 — DEV

Author the skill, then run every **deterministic** check: `make check` (green) and the static advisory tools. No skill is executed here — execution is TEST. (Step set per the Mode table.)

### standards-gate (all modes)

Read `references/standards-gate.md` before invoking skill-creator. It lists all 8 standards in a single-screen table; each owns a domain (per `references/INDEX.md`) and the skill output must conform. For `rewrite`, additionally read `references/equivalence-criteria.md` and `references/e2e-baseline-standard.md`.

### content-placement scan (rewrite only)

Run a **read-only** Explore scan that treats SKILL.md + `references/` as one disclosure surface and emits a **rebalance brief** (MIGRATE / SLIM / HOLD-IN-PLACE), folded into skill-creator's input. The scan NEVER edits, commits, or applies — skill-creator stays the sole writer.

**Guardrail (load-bearing):** the brief's HOLD-IN-PLACE list — gate tables, NEVER / ALWAYS bullets, routing tables, stage-order — MUST NOT be migrated into `references/` (needed at decision time, where references are not loaded). This skill carries `standard-override: disclosure-rule-5` in frontmatter, which widens HOLD-IN-PLACE to cover its inline routing. Full brief contract: `references/content-placement-scan.md`.

**`gate=content-placement` trace.** The scan has no runtime script, so — **AFTER** the scan agent returns (never before) — write the brief to `docs/dogfoods/<skill>/run-NNN/rebalance-brief.md` and append the trace (native `content-placement` kind, no `depth=`). Under `--skip-rebalance` write `verdict=skip` run=0; `create` / `modify` write no trace. Grammar SSOT: [`_shared/references/trace-grammar-contract.md`](../_shared/references/trace-grammar-contract.md).

```bash
source _shared/lib/sh/sandwich-trace.sh
write_gate_trace content-placement skill-writer "$SPEC_HASH" "$RUN" "$VERDICT" \
  "$(git rev-parse --git-common-dir)/flow-dev-sandwich.log" "" "<skill>"
```

**pre-authoring assert (rewrite only).** Before invoking skill-creator, assert the scan ran — missing trace, skip (run=0), or absent `run-NNN` evidence dir all bounce back to this step. `create` / `modify` skip this assert.

```bash
source _shared/lib/sh/sandwich-trace.sh
assert_gate_trace content-placement skill-writer "$SPEC_HASH" stop \
  "$(git rev-parse --git-common-dir)/flow-dev-sandwich.log" || exit 1
```

### skill-creator (author)

Invoke `skill-creator` with: user's request + INTENT dedup findings + the 8 standards (by reference path) + the E2E Baseline report (rewrite) + the content-placement brief (rewrite) — and instruct it to honor the brief's HOLD-IN-PLACE guardrail (never relocate a critical-path item into `references/`). If modifying an existing skill, tell skill-creator to modify the existing SKILL.md rather than create a new directory.

### make check (lint + scripts unit-test = green, HARD STOP)

The one blocking deterministic check. `make check` = `make lint` (SKILL.md readability + trigger-eval JSON parse, static) + `make test` (run the skill's own `scripts/tests/*` unit tests — this is the skill's **red→green** green; a skill is build-less, so there is no separate fan-in artifact to assemble).

| Check | Command / source |
|---|---|
| green | `make check` exits 0 |

**`make check` non-zero → STOP.** Surface the failing tests to the user and fix before the static advisory or TEST. It runs before any probabilistic step so a broken skill fails fast (deterministic-before-probabilistic). Static frontmatter-shape + cross-ref-syntax are re-graded bindingly by the TEST A4 Contract voter — not re-listed here.

### static advisory + eval-write (advisory, all modes)

All **advisory / non-blocking** — surfaces refactor opportunities or backstops a check, never blocks. The binding gate is TEST. These read v2 statically (no LLM dispatch, no skill run); the `--with-llm` semantic leg of `skill-probabilistic-audit` is deferred to TEST. Tool-invocation detail (preflight, exit codes, harness fallback, the rewrite-only references scan + HOLD-IN-PLACE leak check): `references/phase-4-tools.md`.

| # | Tool | Trigger |
|---|---|---|
| `skill-deterministic-audit` | static bloat metrics | has `scripts/` AND SKILL.md > 200 lines AND no `--skip-audit` (note: **AND**, narrower than INTENT audit-v1's `scripts/` **OR** >200 ln — v2 must be large enough to bloat-scan, whereas any prior v1 is worth auditing) |
| `prose-guidelines` (no `--apply`) | prose density | SKILL.md > 200 lines AND no `--skip-audit` |
| `quick_validate` | frontmatter parse | always (advisory; repo conventions win on field-allowlist false-rejects) |
| regression | re-read modified flows | always |

The two audit tools advise on independent axes and **dispatch concurrently** when both trigger. In `rewrite` mode they additionally scan `references/*.md` on a **600-word** per-file trigger + an advisory HOLD-IN-PLACE leak check (`references/phase-4-tools.md`). For `quick_validate`: resolve `$SC_ROOT` with `bash skill-writer/scripts/resolve-skill-creator.sh`, consume only the repo-agreed checks (YAML-parseable, kebab-case `name`, description ≤ 1024, no angle brackets); PyYAML-absent → traced `skip-no-pyyaml`, never a hard error.

**Default-run, not silent-skip (TRACED).** A skipped subsection appends one `gate=advisory:<tool> … verdict=skip-<reason>` line to `.git/flow-dev-sandwich.log` (same log + grammar as the dogfood trace). A TRACE, not a STOP — no hard grep-back assert; the advisory tier is non-blocking. Grammar SSOT: [`_shared/references/trace-grammar-contract.md`](../_shared/references/trace-grammar-contract.md).

The static advisory NEVER edits SKILL.md, NEVER auto-commits, NEVER passes `--apply` to prose-guidelines.

**eval-write.** Refresh evals per `references/trigger-eval-design.md` + `references/contract-standard.md`: read updated description + argument-hint; update `evals/trigger-eval.json` to ≥ 16 cases (≥ 8 pos, ≥ 8 neg); verify `argument-hint`; `make lint` exits 0; commit eval files alongside SKILL.md. **Anti-overfit**: trigger-eval.json should be designed by an agent OTHER than the description author (trigger-eval-design.md Rule 5).

## Stage 3 — TEST

Verify v2 — every **probabilistic** step, after DEV's deterministic green. Two named legs that never merge: the **LLM-review leg** (agents read-and-score v2 without running it) and the **real-execution leg** (agents run the skill on a task). They map to 8-stage integration vs dogfood/e2e; CONTEXT.md *baseline* mandates these axes none-substitutes.

### LLM-review leg

**`skill-probabilistic-audit` (advisory).** The semantic half of the bloat audit deferred from DEV — spawns an Explore subagent to judge redundancy / scriptifiable that the static metrics cannot. Advisory, non-blocking.

**verify-skill 5-voter (MANDATORY — the binding gate).** Runs once per invocation. Verification delegated to `verify-skill` (peer skill); skill-writer owns only the gate decision. Preflight:

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

If the Task tool is unavailable, prefix verify-skill shell calls directly with `VERIFY_SKILL_INVOKED_BY=skill-writer` (fallback detail in `references/phase-6-gate.md`).

| Outcome | Action |
|---|---|
| APPROVE / APPROVE_WITH_NOTES | Pass — print notes; report done |
| NEEDS_HUMAN | BLOCK soft — print 5 ballots; user resolves |
| REJECT | BLOCK hard — print 5 ballots; back to DEV |

Full 9-row exit-code table + the empirical why-it-exists: `references/phase-6-gate.md`.

> **verify-skill constraints** (read-only / single-run / env-gated / no `--mode`) — full list is SSOT in `references/phase-6-gate.md` §Constraints.

### real-execution leg

**resident dogfood (MANDATORY residency gate).** verify-skill's A2 behavior voter runs a *frozen* corpus (anti-gameable, but NOT_APPLICABLE for skills without `test-prompts.json`). Resident dogfood is the complement that runs the skill on a *live* working-tree task — the **absolute** "does v2 work now" axis, catching the "reads fine but breaks when run" class. A dogfood completion trace (or audit-logged skip) is **required** before reporting done.

**Depth by mode**: the `smoke`/`behavior` split is keyed off the Mode table (TEST · dogfood depth row) — not restated here. The rule the table does NOT carry: a `skip-<reason>` (`run=0`) is permitted for `modify` but **NOT for `rewrite`** — a rewrite that did not run a Behavior dogfood bounces.

```bash
bash skill-writer/scripts/dispatch-dogfood-agent.sh <skill-path> [--task <text>]
```

The preparer allocates `run-NNN`, writes a byte-stable dispatch prompt, prints a machine-readable `DOGFOOD_TARGET=<skill-name>` line, and prints it — it does NOT spawn the agent or write the trace; the main agent dispatches AND writes the trace. Evidence: `docs/dogfoods/<target-skill>/run-NNN/{inputs,behavior}/`.

**dogfood completion trace (MANDATORY)** — **AFTER** the preparer returns and the Behavior agent (if any) joined — or on a legitimate skip, never before — write the `gate=e2e-pass:skill-writer` trace via `write_gate_trace`. Field order, the `depth=<smoke|behavior>` load-bearing trailing space, `spec_hash` provenance, and the skill-writer-only `target=<skill>` field (ties the trace to `docs/dogfoods/<target>/run-NNN/`, NOT `skill-writer/`) are SSOT in [`_shared/references/trace-grammar-contract.md`](../_shared/references/trace-grammar-contract.md).

**dogfood boundary assert (before done).** `$DEPTH=behavior` for `rewrite`, `smoke` for `modify`:

```bash
source _shared/lib/sh/sandwich-trace.sh
assert_gate_trace e2e-pass skill-writer "$SPEC_HASH" stop "$(git rev-parse --git-common-dir)/flow-dev-sandwich.log" "$DEPTH" || exit 1
```

Stop mode binds: missing trace, a skip (run=0), or an absent `run-NNN` dir all bounce (match-grammar + run-NNN cross-check mechanics: SSOT in `_shared/references/trace-grammar-contract.md`). A main-agent self-check, not a hook — fabricating BOTH the line AND a matching empty dir still defeats it (accepted ceiling; hook infra declined).

**e2e-AB-compare (rewrite only).** The **comparative** "did v2 beat v1" leg: run v2 through the same 5 dimensions the INTENT baseline measured v1 on, then present the A-vs-B comparison to the user. **CONSUMES the INTENT-frozen A-side by reference** — never re-captures it (re-capture would drift the trust root into self-grading). **auto-PASS is forbidden** — the user reviews the 5-dim AB report. Distinct from dogfood (absolute, no A-B): both run for a rewrite, neither substitutes for the other. Protocol: `references/e2e-baseline-standard.md`.

**5a trigger-eval live (advisory).** Optionally run the corpus against a LIVE model to measure whether the description ACTUALLY triggers — the dynamic leg verify-skill (static) lacks. **ADVISORY**; never auto-PASSes or auto-blocks. **Skip when the description is frozen** (the grep is the SSOT decision, not the mode — a modify that edits the description RUNs):

```bash
base=$(git merge-base origin/main HEAD)
git diff "$base" HEAD -- <skill>/SKILL.md | grep -qE '^[-+]description:'
# exit 0 => description changed => RUN ; exit 1 => frozen => SKIP (verdict=skip-desc-frozen)
```

The **anti-self-grading invariant** (`run_eval` output is a measurement only, NEVER wired into a description mutator) is SSOT in `references/trigger-eval-design.md`. Prepare with `bash skill-writer/scripts/dispatch-trigger-eval-agent.sh <skill-path> [--runs <N>]` (default 2; preparer allocates `run-NNN`, prints the invocation, does NOT spawn or trace). Traced skips: `skip-no-skill-creator` / `skip-no-corpus` / `skip-no-auth` — never a hard fail or a fake all-False. Write the `gate=trigger-eval:skill-writer` trace AFTER the runner returns; the boundary assert is **SOFT** (`warn`, never `exit 1` — only verify-skill can block):

```bash
source _shared/lib/sh/sandwich-trace.sh
assert_gate_trace trigger-eval skill-writer "$SPEC_HASH" warn "$(git rev-parse --git-common-dir)/flow-dev-sandwich.log"
```

## Flow Complete

Summarize outcomes (skill created/modified, gate verdict, any APPROVE_WITH_NOTES). Point user to next action: re-invoke skill-writer to revise, or merge via flow-dev once PR is ready.

```
skill-writer: modify my-skill — APPROVE_WITH_NOTES (verify-skill)
gate=e2e-pass:skill-writer spec_hash=a1b2c3d4e5f6 run=3 verdict=ok depth=smoke target=my-skill
Next: open PR via flow-dev.
```

## When to Use

| Scenario | Action |
|---|---|
| "Create a skill for X" | Full flow: INTENT(dedup) → DEV(create) → TEST(verify-skill) |
| "Improve / add feature to skill X" | INTENT(dedup + audit-v1) → DEV(modify) → TEST(verify-skill equivalence) |
| "Rewrite skill X (v1→v2)" | **INTENT(baseline MANDATORY)** → DEV → TEST(verify-skill effect + e2e-AB) |
| "Audit / is this script still used / score skill X" | Read-only — route to the *Audit dispatch* table above and STOP (no stages) |

## Important Rules

- **Route first** — an audit/read verb on an existing skill is read-only (dispatch + STOP); a build verb enters the stages.
- **Always sweep first** (INTENT dedup) — no exceptions.
- **audit-v1 is advisory + condition-gated** — runs skill-deterministic-audit + prose on the EXISTING version when a prior version exists AND (has `scripts/` OR >200 ln); NEVER runs darwin (self-grading via `results.tsv`).
- **E2E baseline mandatory for `rewrite`** — no `--skip-e2e-baseline`; auto-PASS forbidden; A-side frozen at the INTENT boundary, consumed by-ref at TEST.
- **`make check` (DEV) is a hard STOP** — must exit 0 before any advisory or TEST step; deterministic before probabilistic.
- **verify-skill (TEST) is mandatory** — 5-voter gate; never edits SKILL.md, never commits, never auto-retries; must NOT pass `--mode` (auto-detect).
- **Dogfood residency (TEST) is MANDATORY** — a `gate=e2e-pass:skill-writer` trace (smoke for `modify`, behavior for `rewrite`) or an audit-logged skip is required before done; `rewrite` may not skip.
- **TEST's two legs never merge** — LLM-review (read-and-score) ≠ real-execution (run the skill); e2e-AB (comparative) ≠ dogfood (absolute).
- **No BUILD stage** — a skill has no fan-in artifact and no build≠use; `make check` is DEV's green (ADR 0004).

## See Also

- A skill's `scripts/*.sh` and `scripts/*.py` are code — `coding-guidelines` Comments (why-not-what) applies there. SKILL.md body prose is governed by `prose-guidelines`.
- `references/principles.md` — the seven authoring principles + retention guardrail + two modes
- `references/INDEX.md` — full directory map + conflict resolution
- `references/standards-gate.md` — DEV pre-flight checklist
- `docs/dogfoods/README.md` — dogfood cumulative-iteration convention
- ADR 0004 — the 3-stage INTENT/DEV/TEST model (why no BUILD)
- **Audit engines** — to audit (not build) a skill, see the *Audit dispatch* table above: `skill-audit` for a holistic one-report read, or a per-axis engine direct; all are standalone and also trigger directly.
