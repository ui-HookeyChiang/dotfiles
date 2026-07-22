---
name: prose-guidelines
description: Five principles for tight prose in any artifact — a SKILL.md, engineering spec, README, design doc, code comment, or commit/PR body (NOT code itself, NOT essays/blog/slides), the prose counterpart to coding-guidelines. Apply them WHILE writing — e.g. "write a spec", "draft this doc", "add a code comment", "write the PR description", "how do I write this tightly", "prose writing principles", "寫作原則" — on every prose write even when tightness is not named. To AUDIT existing prose against the same principles, run the detection flow — e.g. "is this section too long", "audit this spec for wordy paragraphs", "幫我壓縮這份 spec", "rewrite verbose prose", "find redundant paragraphs", "find weasel words", "scan for meta self-reference", "any hedges", or --apply — which finds and optionally rewrites violations. Preserves every actionable / technical fact. For scriptifiable repeated instructions, use skill-audit.
argument-hint: <path-to-md-file> [--apply]
landing-group: workflow
---

# prose-guidelines

Compress verbose prose in **SKILL.md** or **specs** while preserving every fact. Detect candidate paragraphs (with ratio), optionally rewrite.

**Prompt-driven** — detection agent reads `references/prose-compression-prompt.md`. Main agent: spawn → validate → present → optionally apply.

## Principles

Standard for tight prose (SKILL.md, spec, README, code comment, commit/PR body). Same five apply to *writing* and *auditing*. Counterpart to `coding-guidelines`.

1. **Cut what does no work.** ("in order to" → "to", doubled words). Test: sentence loses a fact? No = cut.
2. **One idea per sentence, one topic per paragraph.** Break run-ons. Test: delete a sentence, lose a fact? No = delete.
3. **Active verbs.** "perform analysis" → "analyze". Keep passive where actor irrelevant; imperative for steps. Test: noun hiding a verb?
4. **Say it straight.** Drop hedges/intensifiers; give a number or cut; one term per concept. Test: removing word changes meaning? No = noise.
5. **No meta.** Don't narrate the document; say the thing.

**Retention guardrail**: never cut a precondition, caveat, contract, disambiguation, or error-recovery step — those are facts.

Philosophy: cut redundancy, keep complete sentences. NOT caveman (chat output compression); artifacts need readable grammar. Scope: SKILL.md / specs / technical docs.

**Two modes (body-routed).** **Writing** → apply five directly, no tool. **Auditing** (compress / find weasel words / `--apply`) → detection flow below. Mixed: existing target or `--apply` selects Auditing; otherwise Writing.

## When to use

| User intent | Fit | Why |
|---|---|---|
| "Is this Background section in flow-dev/SKILL.md too wordy?" | yes | SKILL.md prose audit |
| "Audit my spec at docs/spec/archive/foo.md for compressible paragraphs" | yes | Spec prose audit |
| "Rewrite this verbose paragraph more tightly" | yes | Single-paragraph rewrite |
| "Find redundant paragraphs in this skill" | yes | SKILL.md scan |
| "Find weasel words in this SKILL.md" (find-weasel) | yes | B1/B2/B3/B4 lexical class — bypasses paragraph ratio gate |
| "Scan for meta self-reference paragraphs" (find-meta) | yes | A4 meta class — deletes meta sentence(s) only; fact-bearing remainder survives |
| "Any hedges in the TL;DR or Summary?" (find-hedge) | yes | E4 hedge class — scoped to first paragraph / `## TL;DR` / `## Summary` |
| "Rewrite `make a decision` / `進行分析` as a verb" | yes | B3 nominalization — verb-noun → active verb |
| "Emit YAML spec draft for flow-dev cleanup pipeline" | yes | Default (no-`--apply`) mode emits paragraph findings with `semantic_axis: G7` — successor to retired `skill-semantic-audit --axis G7` |
| "Compress this blog post" / "Tighten this slide deck" | **no** | Out of scope (essay / long-form / no real prose) |
| "Find paraphrased duplicates across two SKILL.md files" | no | Use `skill-audit` (deterministic pre-filter + probabilistic G1 LLM verdict) |
| "Find scriptifiable bash chains in this SKILL.md" | no | Use `skill-audit` (deterministic metrics + probabilistic LLM 6-axes) |
| "Score my SKILL.md on a rubric" | no | Use `darwin-skill` |

## Scope boundary

**In scope**: SKILL.md, engineering spec (`docs/spec/`, `docs/adr/`), README-style docs.

**Out of scope**: essay, blog, slide deck, narrative, marketing — stylistic rhythm trumps compression. Thresholds tuned for instructional/technical prose; long-form produces false-positive floods.

## Three-step flow

```
1. Detect    — spawn detection agent, get YAML findings array
2. Validate  — main agent enforces evidence_quote substring + line bounds + Gates 7/8
3. Rewrite   — present findings; --apply triggers Edit-by-line-range replacement
```

### Step 1: Detect

**Model**: default **`sonnet`** (Sonnet 4-6) — low validator drop rate. Haiku is ~5× cheaper but drifts 5–10% on ratio ≥ 0.8; use only for large cost-sensitive batches.

```
Launch 1 agent (subagent_type: general-purpose, model: sonnet):
  Read references/prose-compression-prompt.md for the contract.
  Target file: <user-provided-path>

  For each prose paragraph (≥ 2 sentences, ≥ 30 words, not in a code
  fence, not a heading, not a list/table row — exact extraction rule in
  references/prose-compression-prompt.md):
  - Rewrite as tightly as possible preserving every actionable fact
  - Compute original_words, rewritten_words, ratio
  - Pick evidence_quote (literal substring of original)
  - Set confidence (high <0.5, med 0.5-0.7, low 0.7-0.8)
  - SKIP any paragraph with ratio ≥ 0.8 (do NOT emit it)

  Return ONE YAML document:
    file: <abs-path>
    findings: [list per references/prose-compression-prompt.md output schema]
    summary: {total_paragraphs_scanned, flagged_below_0_8,
              high_severity_below_0_5, findings_by_class}
```

One finding **per class per paragraph**. Track `preceding_heading` for heading suppression. **Suppression set** (downgrade one level): `why | rationale | background | 為什麼 | 背景 | 理由 | tutorial | walkthrough | overview | introduction | 教學 | references | see also | further reading | notes`. Mixed-language matches either token.

### Step 2: Validate (mandatory — single-writer principle)

Main agent **must** run before showing findings:

```bash
bash scripts/validate-findings.sh <agent-yaml-output> <target-file>
```

Detector claims; validator enforces. **Do not skip** — agents hallucinate substrings. Runs deterministic gates including **drop budget** `max(3, ceil(0.15 * len(findings)))`: budget reached → exit 1, discard entire batch. Exit: 0=ok, 1=invalidated, 2=bad input. Full gates in [`references/validator-internals.md`](references/validator-internals.md).

`confidence` is advisory — validator verdict binding. `finding_class` REQUIRED (missing → dropped); `lexical_hits` required when `finding_class == lexical`.

### Step 3: Present and (optionally) rewrite

After validation passes, present findings as a table:

| # | Lines | Class | Heading | Ratio | Confidence | Original (excerpt) | Rewritten (excerpt) |
|---|---|---|---|---|---|---|---|

**Class** column: `finding_class` (`paragraph`/`lexical`/`meta`/`hedge`). Lexical: surface `lexical_hits` array.

**No `--apply`** = emit findings only (flow-dev bridge); paragraph findings carry `semantic_axis: G7`. **`--apply`** lands edits.

On `--apply`, do NOT hand-roll or use `git apply` (~30% line-context failures). Run validated YAML through `merge-findings.py`:

```bash
# explicit target path so it never depends on YAML `file:` resolution
python3 scripts/merge-findings.py <validated.yaml> <target-file>
```

It emits JSON (`{file, units:[{lines,start_line,end_line,old_string,new_string,sources}], skipped:[...]}`). Apply contract:

- **Bottom-up order**: `units` is pre-sorted by `start_line` **descending** — iterate top-to-bottom, one `Edit(old_string, new_string)` per unit against the **raw** file, and earlier edits never shift later line numbers.
- **Raw-text match**: `old_string` is verbatim raw range text (validation's whitespace-normalization is internal only). A unit whose `old_string` is not **unique** in the raw file goes to `skipped[]` (no fuzzy match) — surface those, do not force-apply.
- **Same-range merge**: findings on one range collapse to a single unit. Non-zero exit only on **overlapping-but-distinct** ranges (G4(b)) — surface and abort apply.
- **Meta is sentence-level**: a `meta` finding deletes only its meta sentence(s); a `lexical`/`paragraph` finding on the same range applies to the surviving remainder. They conflict (meta wins) only when both target the *same* sentence.
- **Hedge confirmation**: a unit whose `sources` include `hedge` warrants a user confirm before Edit (hedge removal can change stated certainty).
- Structural reformatting (parallel→table, sequential→list) is deferred to a future `--scaffold` mode; not implemented.

Full merge/apply algorithm + JSON shape + sentence-splitter rules: [`references/validator-internals.md`](references/validator-internals.md).

## Severity rubric

Splits by `finding_class`. **Paragraph** uses ratio gate; **lexical/meta/hedge** bypass it (hit-count scoring). Single threshold set; scoped to SKILL.md / spec.

**Sub-table A — paragraph class** (ratio-based):

| Ratio | Severity | Suppressed heading? |
|---|---|---|
| < 0.5 | HIGH | downgrades to MED |
| 0.5–0.7 | MED | downgrades to LOW |
| 0.7–0.8 | LOW | suppressed |
| ≥ 0.8 | not reported | — |

**Sub-table B — lexical / meta / hedge class** (hits-based, ratio gate bypassed):

| Finding class | rule | Severity | Suppressed heading? |
|---|---|---|---|
| lexical | ≥ 3 hits **within one HIGH-eligible sub-class** (B1/B2/B4/B5) | HIGH | downgrades to MED |
| lexical | 2 hits, or cross-class (no HIGH-eligible sub-class reaches 3), or any B3 count | MED | downgrades to LOW |
| lexical | 1 hit | LOW | suppressed |
| meta | (any meta marker) | HIGH | — |
| hedge | ≥ 1 in decision-layer | MED | `## Risks` / `## Assumptions` / `## 風險` / `## 假設` suppresses |

Orchestrator reads validator-emitted `severity_recount` (authoritative); do NOT re-derive from sub-table B. Detail in [`references/validator-internals.md`](references/validator-internals.md).

## Edge cases

| Input | Behavior |
|---|---|
| Empty file | `findings: []`, summary scanned 0; exit 0 |
| All code blocks, no prose | Same — paragraph extraction skips fences |
| Slide deck (`- item` heavy, no prose) | `findings: []`. Out of scope; empty result is honest, not silent success |
| File > 800 lines | Main agent chunks into ~500-line windows BEFORE spawn; one agent call per window |
| Mixed-language heading | Suppression matches by substring on each token |
| Agent returns malformed YAML | Validator exits 1; main agent retries once, then surfaces error |

## Relationship to sibling audits

| Skill | Layer | Output |
|---|---|---|
| `skill-audit` (deterministic leg) | intra-file syntax metrics + cross-skill rule pre-filter (G1/G8) | Python detector + spec draft |
| `skill-audit` (probabilistic leg) G1 / G8 | cross-skill duplication LLM verdict / progressive disclosure | Python detector + YAML findings + spec bridge |
| **`prose-guidelines`** (this) | **prose-level** — paragraph / lexical / meta / hedge | Prompt + agent + YAML findings + optional Edit-by-line-range |

Paragraph findings carry `semantic_axis: G7` for downstream consumers. Default mode = YAML bridge for flow-dev; `--apply` = in-file rewrite.

## References

- `references/prose-compression-prompt.md` — agent prompt + schema + few-shot examples
- `references/validator-internals.md` — full gate list, merge/apply algorithm, JSON shape
- `scripts/validate-findings.sh` — multi-gate verifier
- `scripts/merge-findings.py` — apply planner
- `evals/trigger-eval.json` — trigger routing eval
