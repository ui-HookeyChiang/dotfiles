# Content-placement scan (rewrite mode only)

The DEV · content-placement scan is a **read-only** Explore agent, `rewrite` mode
only, after the standards-gate and before `skill-creator`. It treats
`SKILL.md` + `references/` as one disclosure surface and emits a **rebalance
brief** (≤ 200 words) for skill-creator. The scan NEVER edits, commits, or
applies — skill-creator is the sole writer.

## The brief: three lists

- **MIGRATE** — over-inline *derivation / detail* in SKILL.md, each with a
  target reference file (e.g. `TEST verify-skill exit-code table → phase-6-gate.md`).
  Derivation only, never critical-path (see HOLD-IN-PLACE).
- **SLIM** — `references/*.md` over 600 words (`wc -w`), each with a compress
  target (~300 words, per `disclosure-standard.md` L43).
- **HOLD-IN-PLACE** — critical-path content that MUST NOT move out of SKILL.md:
  - gate decision tables (yes/no paths)
  - NEVER / ALWAYS constraint bullets
  - routing / dispatch tables
  - stage/phase-order structure

  The guardrail list: skill-creator MUST NOT relocate any item here
  into `references/`.

**Empty lists are valid.** Any list may be empty — MIGRATE-only or SLIM-only is
normal; an all-empty brief ("already balanced") runs and traces. With **no
`references/` dir yet** (fat-SKILL.md case), MIGRATE may name *new* files and
SLIM is empty. The scan never fails on empty input.

## Why the guardrail

`references/` is NOT loaded at decision time (`disclosure-standard.md` Rule 1:
"if Claude needs it on every invocation, it lives in the main file"). Migrating
a gate table or NEVER-clause into references is behavior-equivalent on
`test-prompts.json` (A2/A3 PASS) yet breaks disclosure. HOLD-IN-PLACE
forbids that move structurally.

## Orchestrator override

`disclosure-standard.md`'s **Override** clause (NOT Rule 5 itself — Rule 5 is
the ≤500/≤200-line *budget*; the Override is keyed by the marker
*named* `disclosure-rule-5`) lets orchestrators (e.g. `flow-dev`,
`skill-writer`) keep longer main files so routing stays visible.

The marker is `standard-override: disclosure-rule-5` in the skill's **SKILL.md
frontmatter** — where `standards-gate.md` step 2 consumes it, so frontmatter is
**authoritative**. `disclosure-standard.md` also asks for a justification line in
`INDEX.md` (an audit note). The scan checks **both** and, when present, **widens
HOLD-IN-PLACE** to cover the routing the override protects — so a naive
"slim to ≤ 500 lines" cannot damage intentional routing.

## Scan output

After the scan agent returns, the main agent writes the brief to
`docs/dogfoods/<skill>/run-NNN/rebalance-brief.md`. A pre-authoring check
(`test -d run-NNN`) refuses skill-creator without evidence.
`--skip-rebalance` skips the scan entirely.

## Scan agent brief (inline dispatch from SKILL.md DEV · content-placement scan)

    Launch 1 agent (subagent_type: Explore):
      Read-only. Do NOT edit, write, or commit any file.
      Target skill: <skill-path> (rewrite mode).
      1. Measure v1 disclosure split: wc -l SKILL.md; wc -w each references/*.md.
      2. Read SKILL.md frontmatter (authoritative) AND references/INDEX.md
         (audit note) for `standard-override: disclosure-rule-5`.
      3. Classify SKILL.md content: derivation/detail (MIGRATE-eligible) vs
         critical-path (HOLD-IN-PLACE: gate tables / NEVER-ALWAYS bullets /
         routing / phase-order). Honor the override (widen HOLD-IN-PLACE).
      4. List references/*.md over 600 words (SLIM). Any list may be empty.
      Return a ≤200-word brief: MIGRATE / SLIM / HOLD-IN-PLACE lists. No edits.

## One-way flow

scan → skill-creator writes → DEV · make check + static advisory verify. There is no edge from
DEV verification back into the author loop — NOT a livelock, so no cycle cap needed.
