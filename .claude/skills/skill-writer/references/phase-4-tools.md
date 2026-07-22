# DEV static advisory + TEST LLM-review — audit tool invocation details

Invocation details for the audit tools the DEV static-advisory step and the TEST
LLM-review leg dispatch. The two advisory subsections (`skill-audit`,
`prose-guidelines`) are **advisory / non-blocking** — they surface refactor
opportunities and never block flow. The mandatory hard gate is TEST · verify-skill
5-voter.

## INTENT · audit-v1 — the v1 leg of the audit pair

INTENT · audit-v1 (SKILL.md, during the INTENT stage before authoring) runs the same advisory audit family on the
**existing** version, *before* authoring. It shares this file's mechanics (the
`gate=advisory:<tool>` skip-trace convention below); only the artifact and timing
differ. The detail the SKILL.md body defers here:

**Before/after pairing (why it is not a duplicate of DEV static advisory).** INTENT · audit-v1 audits v1
to answer *"what was wrong with the existing skill?"* — its findings feed DEV · skill-creator
(what the rewrite should fix / delete). DEV static advisory audits the v2 draft to answer *"did
the rewrite fix it / introduce new bloat?"* — the read verify-skill leans on. Same
engine on the *same* artifact twice would be waste; v1-vs-v2 is a before/after pair
on different artifacts. The deterministic-audit (deadcode/reachability) runs **only** in INTENT · audit-v1 (there is no
DEV static advisory deadcode step) — it is the net-new pre-authoring read; syntax/prose run in
both (INTENT · audit-v1 on v1, DEV static advisory on v2).

**Collect, never merge, never auto-apply.** INTENT · audit-v1 invokes `skill-audit` + prose
on v1, each via its *Audit dispatch* command. Their outputs are **collected verbatim,
each in its native paradigm** (metric brief / prose findings / reachability graph)
into `docs/dogfoods/<skill>-vN/iteration-M/audit-brief.md` — NO cross-engine merge
(3 incompatible data models). The brief is advisory
**design input** to DEV · skill-creator; it is NEVER wired into an auto-mutator (same firewall as
`run_eval`). darwin is excluded — see the SKILL.md NOT-clause (`results.tsv`
self-grading hazard, CONTEXT.md `_Avoid_`).

**Skip reasons (traced, same convention as below).** `skip-no-prior` (no prior version
— create mode, or rewrite of a brand-new skill), `skip-under-threshold` (modify of a
skill with no `scripts/` AND ≤ 200 lines — keeps a one-line tweak cheap),
`skip-audit-flag` (`--skip-audit`). A skipped engine writes its skip line; a run leaves
none. INTENT · audit-v1 is advisory tier — no hard grep-back assert, TEST · verify-skill stays binding.

## Traced default-run (applies to both 4.1a and 4.1b)

Each subsection has a trigger condition. When the condition holds, the tool
**runs** and passes findings to the user. When it is skipped (trigger false,
`--skip-audit`, or preflight fail), the skip is **not** silent — by convention
the agent appends one line to `.git/flow-dev-sandwich.log` (the SAME log +
grammar as TEST · resident e2e-pass's `gate=e2e-pass` trace — one mechanism, not a fork):

```
<ISO8601-UTC> gate=advisory:<tool> spec_hash=<12hex> run=<NNN> verdict=skip-<reason>
```

- `<tool>` ∈ {`deterministic-audit`, `prose-guidelines`}. `<12hex>` is
  `git hash-object <spec> | cut -c1-12` (the SAME `spec_hash` the sandwich
  sidecar, spec-advisory, and dogfood traces compute — one computation).
- `<reason>` examples: `no-scripts`, `under-200loc`, `skip-audit-flag`,
  `dispatch-fail`. A run that fires leaves no skip line.
- This is a TRACE, not a STOP, and there is no hard grep-back assert (unlike
  TEST · resident dogfood's `STOP-SAFE` or trigger-eval's `WARN`) — the advisory tier is
  non-blocking by design, so the skip line is a discipline the agent follows,
  not a mechanically-enforced gate. The line makes "ran but did not apply"
  auditable, distinct from "never reached".
- **Carve-out — references-skip is EXEMPTED (rewrite mode only).** The
  `rewrite`-mode references scan (4.1a-ref / 4.1b-ref below) does **not** write a
  per-file skip trace line, even though it is otherwise advisory. This is a
  deliberate exception to the "skip is not silent" convention above: a per-file
  trace would be noisy because references seldom trigger. Instead, a single
  one-line `references:` summary appears in the 4.1a/4.1b
  report (see 4.1b-ref). The invariant: SKILL.md skips still trace; references
  skips summarize. `create` and `modify` modes never run the references scan, so
  this carve-out applies only in `rewrite` mode.

## 4.1a skill-audit (DEV · static advisory `--no-llm` half)

Conditional: run only if (a) the skill has a `scripts/` directory,
(b) `SKILL.md > 200 lines`, and (c) the user did not pass
`--skip-audit`. If any condition fails, emit the `gate=advisory:deterministic-audit
… verdict=skip-<reason>` trace line above (do not silently skip).

**Stage placement:** the `--no-llm` metrics-only invocation is DEV · static advisory
(deterministic, no LLM dispatch). The `--with-llm` semantic leg (spawns Explore
subagent) is TEST · LLM-review (probabilistic). They are separated at stage boundary;
this section documents both.

Default invocation: `bash ~/.claude/skills/skill-audit/scripts/run.sh <skill>`
— runs deadcode reachability + syntax metrics + semantic prefilter. Outputs
findings per leg.

Exit codes:
- `2` — all legs clean; print one-line verbose, complete
- `0` — at least one leg found a problem; print report + advisory note
- `1` — a leg errored; print stderr verbatim

Legacy detector path: `bash ~/.claude/skills/skill-audit/scripts/syntax_audit.sh <skill>/SKILL.md --no-spec` retained for CI / dogfood backward compatibility; not the DEV static advisory default.

### 4.1a-ref skill-audit on references/ (rewrite mode only)

Conditional: run only if (a) `skill-writer` is in `rewrite` mode, (b) the skill
has a `scripts/` directory, (c) the reference file is `> 200 lines`, and (d) the
user did not pass `--skip-audit`. Applied **per reference file** to each
`references/*.md` that meets (c). **Fires rarely for typical skills** but
**routinely for orchestrators** — a small skill's references seldom clear 200
lines, yet an orchestrator with `scripts/` and large references (e.g.
`flow-dev` has 4 references > 200 lines) trips (b)+(c) on several files at
once. Kept for mechanism consistency with SKILL.md's DEV static advisory, not as a primary value
source. The skip-trace exemption applies: a skipped
or non-triggering reference writes **no** trace line; its status folds into the
shared `references:` report summary (see 4.1b-ref).

## 4.1b prose-guidelines

Conditional: run only if `SKILL.md > 200 lines` AND user did not pass
`--skip-audit`. **scripts/ presence is irrelevant** for 4.1b (unlike
4.1a) — prose density is what matters. If a condition fails, emit the
`gate=advisory:prose-guidelines … verdict=skip-<reason>` trace line above.

Invocation: `Skill prose-guidelines <skill>/SKILL.md` (advisory mode;
**never pass `--apply`** from DEV static advisory).

Exit codes:
- `0` — findings present (compressible paragraphs, ratio < 0.8); print
  top-3 findings + advisory note
- `2` — no compressible paragraph; print one-line verbose
- `1` — validator drop budget exceeded / dispatch failure; print
  stderr + non-blocking advisory

### 4.1b-ref prose-guidelines on references/ (rewrite mode only)

This is the **references main path** — where the rewrite-mode references scan
earns its keep (4.1a-ref above is the rare-fire companion).

Conditional: run only if (a) `skill-writer` is in `rewrite` mode, (b) the
reference file's word count is `> 600` (`wc -w <ref>`), and (c) the user did not
pass `--skip-audit`. Applied **per reference file** to each `references/*.md`.
**CRITICAL:** this is a **600-word** gate, NOT SKILL.md's 200-line gate — the
unit is aligned to `disclosure-standard.md` L43, which sets the references
bloat threshold:

> `references/` file > 600 words → split or compress to working-draft (~300 words)

SKILL.md's own 4.1b trigger stays the 200-line gate; only the references scan uses
the 600-word unit.

Invocation: `Skill prose-guidelines <skill>/references/<file>.md` per triggering
file (advisory mode; **never pass `--apply`**). Exit codes match 4.1b above.

Output schema: reference findings merge into the **single** 4.1a/4.1b advisory
report — no separate report. That report gains a `references:` section, with each
finding tagged `檔名:行號` (e.g. `phase-4-tools.md:64`). When **no** reference
file triggers, the `references:` section prints a one-line summary instead of
per-file detail — e.g. `references: N 檔皆 ≤ 600 words, 未觸發`. This one-line
summary is what replaces the per-file skip trace (the carve-out in "Traced
default-run" above): references skips summarize, they do not trace.

### 4.1-ref HOLD-IN-PLACE leak check (rewrite mode only, advisory)

After 4.1a-ref / 4.1b-ref, perform one advisory check: read the v1 snapshot
(captured by INTENT · E2E baseline A-capture at
`docs/dogfoods/<skill>-vN/iteration-M/v1-snapshot/`) and confirm that **no
HOLD-IN-PLACE item** (the DEV · content-placement scan brief's critical-path list — gate
tables / NEVER-ALWAYS bullets / routing / stage-order) was relocated from v1's
SKILL.md into v2's `references/`. The brief contract lives in
`references/content-placement-scan.md`; this check is its post-write counterpart.

- **Advisory only — never blocks.** It folds into the existing one-line
  `references:` report summary; it adds no separate report and no STOP. The
  skip-trace carve-out above (references skips summarize, do not trace) is
  unchanged.
- **v1-snapshot precondition.** The check requires the INTENT · E2E baseline A-capture snapshot. Since
  INTENT · E2E baseline A-capture is MANDATORY for `rewrite` mode (no `--skip-e2e-baseline`), the
  snapshot is guaranteed present for any rewrite that reached DEV static advisory. If the
  snapshot is somehow absent (manual tampering), record
  `HOLD-IN-PLACE: skipped (no v1 snapshot)` in the `references:` summary rather
  than erroring — it never errors and never blocks. The snapshot is frozen at
  the INTENT boundary, so staleness vs. the v1 the rebalance started from is not a concern.
- **Matching is best-effort, not authoritative.** The detector is a coarse
  textual presence check: a HOLD-IN-PLACE block present in v1 SKILL.md that now
  appears only under v2 `references/`. A reworded / paraphrased relocation can
  evade an exact textual match — an accepted limitation, stated honestly. This
  is NOT the real guardrail: the **binding** protection is (a) the
  DEV · content-placement scan brief instructing skill-creator not to migrate
  critical-path, and (b) TEST · verify-skill 5-voter A2/A4 voters re-grading the v2
  disclosure surface. The leak check is a cheap early-warning, not a proof.
- On a detected leak: surface the finding with the v1 location (e.g.
  `leak: routing-table was at SKILL.md → now in references/phase-N.md`). The user decides
  (typical path: accept and proceed to TEST · verify-skill; or run a `modify` invocation
  post-merge to correct).
- On a clean run: the `references:` summary notes `HOLD-IN-PLACE: 0 leaked`.

## Tools NOT dispatched in the advisory flow

These audit tools are deliberately **not** part of the DEV static advisory or
TEST LLM-review legs; each remains available standalone (see SKILL.md "See Also"):

- **`darwin-skill`** — opt-in single 0-100 score. Its axes are subsumed by
  verify-skill (structural → A4/A1, effect → A2); single-scorer + the
  `results.tsv` self-scoring hazard make it unfit as a flow gate. Run
  `Skill darwin-skill <skill>` standalone (no hill-climbing, no SKILL.md edits,
  no commits) if a number is wanted.
- **`skill-audit`** — the live G1 cross-skill-duplication engine
  (SKILL.md *Audit dispatch* table). Not a flow leg here: its prose-density axis
  is owned by `prose-guidelines`, and within the build flow the INTENT · dedup
  sweep's ≥2-SKILL.md clause already exercises G1; progressive-disclosure (G8) ≈
  `disclosure-standard` / A2. Run `Skill skill-audit` directly for
  an ad-hoc G1/G8 pass.

## Common patterns

- Both DEV static advisory tools are advisory; never block the flow (TEST · verify-skill is binding).
- Conditional invocation: each subsection has its own trigger condition
  (LOC threshold, `scripts/` presence, `--skip-audit`); a skipped condition
  emits a `gate=advisory:<tool>` trace, never a silent drop.
- Output: composite scores or ranked findings → user; user decides
  whether to iterate.
- DEV static advisory NEVER edits SKILL.md, NEVER auto-commits, NEVER auto-pushes,
  NEVER passes `--apply`.
- Each subsection runs at most once per `skill-writer` invocation
  (no recursion, no auto-loop).
