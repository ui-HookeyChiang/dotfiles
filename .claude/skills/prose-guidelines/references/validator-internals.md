# Validator & apply internals

The SKILL.md summary is the every-invocation critical path; this file is the full derivation for `scripts/validate-findings.sh` and `scripts/merge-findings.py`.

## Anti-hallucination contract (two-layer defense)

| Layer | Job |
|---|---|
| **Detection agent** | Self-report `evidence_quote`, `lines`, `finding_class`, `lexical_hits` (when class is lexical, as `{token, subclass}` objects), `confidence` |
| **Validator script** | Independently verify substring + line-range bounds + `finding_class` ∈ known set + `lexical_hits` present when lexical; **Gate 7** (fact-token preservation) + **Gate 8** (CJK-aware ratio recount); **relative drop budget** `max(3, ceil(0.15 * len(findings)))` = batch invalidation |

This is the PUA-harness "separation of self-evaluation and action" rule.
The detection agent claims to validate; the validator script enforces.

## Validator gates

1. **Gate 1 — line bounds**: `lines` matches `L\d+-L\d+` and `1 ≤ start ≤ end ≤ file_line_count`.
2. **Gate 2 — evidence substring**: `evidence_quote` is a literal (whitespace-normalized) substring of the cited range OR the whole body.
3. **Gate 3 — finding_class**: present and ∈ `{paragraph, lexical, meta, hedge}`.
4. **Gate 4 — lexical_hits**: present and non-empty when `finding_class == lexical`.
5. **Gate 5 — semantic_axis**: `semantic_axis: G7` present **iff** `finding_class == paragraph` (required on paragraph, forbidden elsewhere).
6. **Gate 7 — fact-token preservation** (non-`meta` findings): hard fact tokens extracted from the cited original range must all survive in `rewritten_text`. Fact-token classes: numbers+units, hyphen-units, ranges/codes (`5xx`, `30-50%`, `429`), paths, `--flags`, errno / header-idents, hex / SHA / IP, and CJK+latin negation words (`not`/`never`/`unless`/`except`/`不`/`除非`/`否則`) matched by substring. A token inside a recorded `lexical_hits` span is exempt **first** (deleting a flagged weasel never trips the gate); an unflagged number/errno/path/negation that vanishes drops the finding. `meta` is exempt entirely.
7. **Gate 8 — CJK-aware ratio recount**: recompute `original_words` / `rewritten_words` / `ratio` with the CJK-aware tokenizer (`[A-Za-z0-9]+(?:[.\-/][A-Za-z0-9]+)*|[一-鿿]` — latin run = 1 token, each CJK ideograph = 1 token). Drop on > 0.05 self-report divergence; drop a paragraph-class finding whose **recount** `ratio ≥ 0.8`. The validator overwrites `ratio` with the recount, making the prompt's "validator will recount" promise real.

**Relative drop budget** = `max(3, ceil(0.15 * len(findings)))`. If drops reach the budget in one run → exit 1, **entire batch invalidated** (coincides with a fixed 3 for batches ≤ 20 findings). The detection agent's `confidence` is advisory only; a `confidence: high` finding that fails any gate (substring, missing class, Gate 7/8) is dropped, no exceptions. Missing `finding_class` findings are dropped and count toward the budget; same for missing `lexical_hits` when class is lexical.

**Batch-mode detection**: v2 batch iff the first finding carries a `finding_class` key; a v1 batch uses the fixed-3 budget and no class checks. Mixed batches are rejected per-finding. The validator emits filtered YAML to stdout, drop reasons to stderr, and adds a `summary.validator_dropped` count. Exit codes: 0 = under budget, 1 = batch invalidated, 2 = bad input.

### Gate 7 design basis

Gate 7 derives from the `caveman` skill's **Auto-Clarity** rule — stop
compressing when compression itself creates technical ambiguity (lost
order, omitted conjunctions, collapsed condition branches). See the Gate 7
rationale in `references/prose-compression-prompt.md` for the few-shot
illustrations.

## Severity recount (lexical)

The validator buckets `lexical_hits` by their `{token, subclass}` sub-class
(B1/B2/B3/B4/B5) and computes the `severity_recount` field:

- **HIGH** iff ≥ 3 hits **within a single HIGH-eligible sub-class** (3× B1, *or* 3× B2, *or* 3× B4, *or* 3× B5). **B3 (nominalization) is advisory** — excluded from the HIGH set (it is the field's highest false-positive class), so 3× B3 does NOT escalate to HIGH.
- **MED** for 2 hits, or any cross-class mix where no single HIGH-eligible sub-class reaches 3 (e.g. 1× B1 + 1× B3 + 1× B4 = MED). B3 hits still count toward this `total ≥ 2` MED and are still surfaced in `lexical_hits`; they just cannot reach HIGH on their own.
- **LOW** for a lone hit.

`severity_recount` is **authoritative** — the orchestrator reads it and does
NOT re-derive severity from SKILL.md sub-table B (that table is the
human-readable spec of this computation, not a second source to parse).
Heading suppression still applies on top (downgrade one level when
`preceding_heading` matches the suppression set).

## Merge / apply algorithm (merge-findings.py)

On `--apply`, the validated YAML runs through `merge-findings.py`, which
plans apply ordering + same-range merges and emits JSON on stdout:

```json
{
  "file": "<target path>",
  "units": [ { "lines": "L<s>-L<e>", "start_line": <int>, "end_line": <int>,
               "old_string": "<raw range text>", "new_string": "<merged replacement>",
               "sources": ["meta", "lexical", ...] }, ... ],
  "skipped": [ { "lines": "...", "reason": "old_string not unique in raw file text" }, ... ]
}
```

Apply contract:

- **Bottom-up order**: `units` is pre-sorted by `start_line` **descending**, so applying an earlier Edit never shifts a later one's line numbers. Iterate top-to-bottom, run exactly **one `Edit(old_string=unit.old_string, new_string=unit.new_string)`** per unit against the **raw** target file.
- **Raw-text match (not normalized)**: `old_string` is the verbatim raw file text of the range. The validator's `normws` whitespace normalization is **internal to validation only** — Edit must match raw bytes, so `merge-findings.py` builds `old_string` from the raw file. A unit whose `old_string` does not match **uniquely** in the raw file is reported in `skipped[]` (no best-effort fuzzy match) — surface those, do not force-apply.
- **Same-range merge**: findings sharing one source range collapse into a single unit. The exit code is non-zero only on the **overlapping-but-distinct** ranges conflict (G4(b)); surface that as an error and abort apply.
- **Meta is sentence-level, not whole-paragraph**: a `meta` finding deletes only its own meta sentence(s); a `lexical` / `paragraph` finding sharing the range applies to the surviving **remainder**. They conflict (meta wins outright) only when both target the *same* sentence. The fact-bearing remainder of a meta paragraph is preserved.
- **Hedge confirmation**: a unit whose `sources` include `hedge` still warrants a user confirm before Edit (hedge removal can change the author's stated certainty).
- Structural reformatting (parallel→table, sequential→ordered-list) is deferred to a future `--scaffold` mode; not implemented.

### Sentence splitter

`merge-findings.py` uses a deterministic sentence splitter for sentence-level
meta deletion: a sentence ends at `.!?` + whitespace/EOS, or at CJK `。！？`
(+ optional whitespace); the terminator stays attached to its sentence. No
abbreviation or decimal heuristics — the splitter is intentionally simple so
its boundaries are reproducible.

## Detection / spawn contract

- Default detection model = `sonnet`; Haiku allowed for large batches (5–10% drift on the ratio ≥ 0.8 skip).
- Paragraph extraction: contiguous non-blank block, ≥ 30 words AND ≥ 2 sentences, not in a code fence, not a heading, not a list item (`- * + 1. > |`), not a table row. "≥ 2 sentences" replaces the removed "≥ 2 source lines" proxy.
- Track `preceding_heading` = nearest `^#+ ` line above.
- Output is ONE YAML document: `file`, `findings: […]`, `summary: {total_paragraphs_scanned, flagged_below_0_8, high_severity_below_0_5, findings_by_class:{paragraph,lexical,meta,hedge}, note?}`. `findings_by_class` is REQUIRED in the summary.

## Lexical sub-classes (wordlists owned by prose-compression-prompt.md)

The wordlists themselves live in `references/prose-compression-prompt.md`
(the agent reads that, not this file). Summary of the contract:

- **B1** English weasel (15 words). **B1 adjacent-quantification skip**: do NOT flag a weasel within ±3 tokens of a digit/unit/count.
- **B2** Chinese weasel (11 words).
- **B3** nominalization→verb (English + Chinese mapping; record the whole phrase as the token). **Advisory** — surfaced + counts toward MED, but excluded from the HIGH ≥3 rule (false-positive-prone).
- **B4** intensifier strip (English 9 + Chinese 7; delete unless load-bearing; 3 context exceptions — release-note tone / quotation / comparative).
- **B5** redundant-phrase swap (10-entry table: "in order to"→"to", …) + adjacent-duplicate-word. Deterministic, near-zero FP; HIGH-eligible.
- A token belongs to exactly **one** sub-class (e.g. `其實` is B4, not B2 — no double-count). **B5 precedence: longest matching span wins** — a B5 phrase claims its whole span, so a B1/B4 token only *inside* that span is not separately recorded. `lexical_hits` entries are `{token, subclass}` objects; the validator dedups by surface token.

## Upstream prompt relationship

`references/prose-compression-prompt.md` inherits the canonical paragraph-class
few-shot examples verbatim from `skill-semantic-audit/references/llm-prompts/g7-prompt.md`
and forks them with the lexical / meta / hedge extensions (prose-guidelines-specific).
It overrides the upstream schema only where they diverge; the prose-compression
heuristics, narrative-removal vs. transition-trim examples, and ratio rubric are
identical by reference.
