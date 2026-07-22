# Severity rubric

Severity thresholds for the active axes (G1 / G8; G7 context rules inherited by prose-guidelines), context suppression rules, and the four-rule G8 rule-LLM fusion priority.

## G1 — Cross-skill same-meaning paragraphs

**Detection:** paragraphs (≥ 30 words / ≥ 5 lines) across two or more SKILL.md or `references/*.md` files share the same meaning (literal duplicates **or** paraphrases).

| Severity | Condition |
|---|---|
| HIGH | ≥ 3 skills carry the same-meaning paragraph. |
| MED  | 2 skills carry it **and** the shared content is ≥ 10 lines. |
| LOW  | 2 skills carry it **and** the shared content is < 10 lines. |

No context suppression for G1 — cross-skill duplication is always actionable; the question is only "extract to `_shared/`" vs "single owner + cross-link".

## G7 — Paragraph density

> These rules now live in prose-guidelines (G7 removed from this engine 2026-05-29); retained here as the shared reference.

**Detection:** for every prose paragraph (≥ 3 sentences **or** ≥ 80 words; skip code blocks / tables / list items / headings), an LLM rewrites the paragraph to preserve all technical information at the tightest possible word count. The compression ratio is `rewritten_words / original_words`.

| Severity | Condition |
|---|---|
| HIGH | `ratio < 0.5` — more than half the words can go without semantic loss. |
| MED  | `0.5 ≤ ratio < 0.7`. |
| LOW  | `0.7 ≤ ratio < 0.8`. |
| (not reported) | `ratio ≥ 0.8` — paragraph already terse enough. |

### G7 context suppression — heading-aware downgrade

If a paragraph sits under a heading whose name signals it is **deliberately explanatory** (rather than instructional), drop the finding's severity by one level (HIGH → MED, MED → LOW, LOW → no report). The three suppression buckets are borrowed from `skill-syntax-audit/scripts/audit.py` line 70-82 **as a design pattern**, with regex rewritten for prose context:

| Bucket | Heading regex (case-insensitive) |
|---|---|
| Why / rationale | `^##+\s*(why\b\|rationale\b\|background\b\|為什麼\|背景\|理由)` |
| Teaching / explanatory | `^##+\s*(教學\b\|tutorial\b\|walkthrough\b\|overview\b\|introduction\b)` |
| Reference / context | `^##+\s*(references?\b\|see also\b\|further reading\b\|notes\b)` |

The suppression is one-step only — a HIGH paragraph in `## Why` becomes MED, not LOW. Two stacked suppression headings (e.g. `## Why → ## Background`) still apply only one downgrade.

## G8 — Progressive disclosure violation

**Detection:** SKILL.md contains material that belongs in `references/*.md` — long examples, enumerated edge-case lists, design-history / rationale sections.

| Severity | Condition (lines movable to `references/`) |
|---|---|
| HIGH | ≥ 30 lines movable. |
| MED  | 20-29 lines movable. |
| LOW  | 10-19 lines movable. |
| (not reported) | < 10 lines movable — extraction cost exceeds benefit. |

### G8 rule-LLM fusion priority

G8 runs a **rule layer first** (cheap scan for syntactic hints: long code blocks, enumerated lists, `## Why` / `## Rationale` / `## Design history` headings) and an **LLM layer second** (decides whether the hit is actionable main-flow content or reference material). When the two layers disagree, fusion follows this priority order:

1. **Rule hit + LLM confirms actionable → drop.** The rule found a syntactic match, but the LLM judges the content as part of the main flow that the reader must see at this level. No finding emitted.
2. **Rule hit + LLM judges reference material → report, `confidence: high`.** Both layers agree it should move. Highest confidence — both syntactic and semantic signals align.
3. **Rule miss + LLM independently flags → report, `confidence: medium`.** No rule match, but LLM identified content that should be deferred. Lower confidence — semantic signal only, no syntactic backing.
4. **Rule hit + LLM confirms + movable lines < 10 → drop.** Below the LOW threshold (see severity table); extraction cost outweighs benefit. Confidence is moot.

These four rules form a closed decision matrix — every (rule, LLM) outcome pair maps to exactly one action (drop or report).

### G8 `inline_changelog` sub-kind — DELETE disposition (sidecar)

Distinct from the move-oriented hits above. **Detection:** a bullet-level line carrying a historical marker — an ISO date `\d{4}-\d{2}-\d{2}`, or a change-history verb (`demoted from`, `moved to`, `renamed`, `replaced by`, `no longer`, `formerly`, `as of <date>`, or `was (demoted|removed|renamed|replaced|moved|deprecated|merged|folded|split|retired|superseded)`). The `was \w+ed` form is deliberately restricted to that explicit verb set so plain English ("was tested manually", "was needed") does not over-trigger.

**Disposition = DELETE** (such change-history belongs in git / spec, not the SKILL.md body), **fixed severity MED**, and it **bypasses both `_severity()` and fusion rule 4** — a one-line residue is worth flagging even though its movable-line count is below the move-path threshold. This sidecar path never enters the move-path severity/fusion logic, keeping the four-rule matrix above behaviorally unchanged.

- **LLM confirms removable (classification `reference`/`rationale`) → report DELETE.** In `--no-llm` mode the inline_changelog axis returns a NOT_APPLICABLE advisory (§6 case-3: open concept — no regex whitelist covers the full open set; presenting regex hits as findings is fail-silent). The regex still runs to count candidates for the advisory's INFO summary, but no DELETE finding is emitted. Re-run without `--no-llm` to get actionable results.
- **LLM judges the marker still-in-force (classification `actionable`, e.g. a live migration deadline or version gate whose removal WOULD lose current-state info) → drop.** Route prose-length concerns on such a line to `prose-guidelines` (compress, not delete).
- **Contained-in-move suppression.** If a residue line falls inside the range of a move-path finding emitted in the same run, the `inline_changelog` finding is suppressed — the move review already covers that region, avoiding contradictory dispositions for one line.

### G8 context suppression — same heading buckets as G7

The Why / rationale / teaching / reference heading buckets above also apply to G8: if the rule layer hit a `## Why` or `## Background` heading, the finding's severity is downgraded one level before fusion rule (4) checks the < 10-line threshold. This avoids double-penalising a legitimate explanatory section.

## Confidence assignment summary

| Source | Confidence default | Notes |
|---|---|---|
| G1 rule + LLM both agree (≥ 3 skills) | `high` | strongest signal |
| G1 LLM-only paraphrase detection (2 skills) | `medium` | semantic only |
| G7 ratio < 0.5 | `high` | quantitative basis (`numeric_basis`) |
| G7 ratio 0.5-0.8 | `medium` | quantitative but smaller margin |
| G8 fusion rule (2) | `high` | rule + LLM both confirm |
| G8 fusion rule (3) | `medium` | LLM-only |

The LLM may override these defaults by emitting a different `confidence` value in its structured output. `confidence: low` is reserved for borderline cases where the LLM flags but explicitly notes ambiguity — surfaced in the report but listed last so high-confidence findings stay visible.
