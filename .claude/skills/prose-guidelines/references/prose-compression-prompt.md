# prose-compression-prompt

LLM prompt for the `prose-guidelines` detection + rewrite step. **Single-prompt design** — one agent call returns both detection (ratio, line range, evidence) and rewrite (rewritten_text) in one YAML document.

## Single source of truth

**v2 forks the upstream G7 prompt.** The compression heuristics, narrative-removal vs. transition-trim examples, and ratio rubric for **paragraph-class** findings are forked from the upstream G7 baseline at:

```
skill-audit/references/llm-prompts/g7-prompt.md
```

That file's 3 worked examples (HIGH compression / MED compression / no-op) still apply verbatim to the **paragraph class** here. They are **augmented (not replaced)** by new class-specific detectors below — the **lexical / meta / hedge extensions in this file (B1/B2/B3/B4/B5/A4/E4) are prose-guidelines-specific** and have no G7 counterpart. G7 stays unchanged; prose-guidelines v2 diverges by adding class-specific detectors that bypass the paragraph ratio gate.

## Overrides vs. upstream G7 prompt

| Aspect | G7 (upstream) | prose-guidelines (this) |
|---|---|---|
| **Input granularity** | One paragraph per call | **Whole file per call** — agent extracts paragraphs itself |
| **Output shape** | Single YAML object (one finding) | YAML document with `findings: [list]` (multiple findings) |
| **Finding classes** | Paragraph ratio only | Paragraph + lexical (B1-B5) + meta (A4) + hedge (E4) |
| **File scope** | SKILL.md | SKILL.md or engineering spec |
| **Suggested heading regex** | 11 keywords (G7 set) | Same 11 keywords, plus loose `## Why 為什麼...` substring matching for mixed-language |
| **Confidence field semantics** | Self-report only | Self-report + downstream validator enforcement |

The paragraph-class detection rubric, threshold mapping, and rewrite quality bar **do not change** from G7. Lexical/meta/hedge classes are net-new and have their own emission rules (below).

## System role

You are a documentation editor specialising in technical knowledge distillation. The user has given you one markdown file — a **Claude Skill SKILL.md** or an **engineering spec**. Your job is to find all compressible prose paragraphs in that file and produce a rewrite for each.

**Scope discipline**: this prompt is for SKILL.md and engineering specs. If you detect the input is a slide deck, blog, essay, or long-form narrative document, return `findings: []` and add a `note` to `summary` explaining the out-of-scope detection. Do NOT compress narrative prose with the SKILL.md ratio rubric — it will produce false positives.

Do not invent content. Do not quote anything not in the input. Every `evidence_quote` is programmatically validated against the source file; failures are dropped.

## Input format

The main agent provides a single argument: the absolute path to the target file. Read the file with the standard file-reading tool. **Do not split the file across multiple agent calls** — if the file exceeds the agent's context, the main agent will have pre-chunked it.

## Paragraph extraction rules

A "prose paragraph" is a **contiguous block of non-blank source lines** (separated from other prose by a blank line, heading, list, code fence, or table) satisfying ALL:

- **≥ 30 words** (whitespace split, counted across the whole block — a long single-source-line paragraph that soft-wraps in viewers still counts as ONE source line but as a valid paragraph if it has ≥ 30 words AND ≥ 2 sentences)
- **≥ 2 sentences** (sentences delimited by `.`, `!`, `?` followed by whitespace or end-of-line; this is the canonical "is this real prose" test — a single directive like `Run audit.sh and check exit code 0.` is one sentence and does NOT qualify even if it's > 30 words)
- NOT inside a fenced code block (` ``` ` or `~~~`)
- NOT a heading (line starts with `#`)
- NOT a list item (starts with `-`, `*`, `+`, `1.`, `> `, or `|`)
- NOT a table row (starts with `|`)

**Resolving the "≥ 2 lines" intent**: the older "≥ 2 source lines" rule (now removed) was a proxy for "real prose, not a one-line directive". The proxy was ambiguous because many editors hard-wrap at 80 columns (one logical paragraph = many source lines) and many don't (one logical paragraph = one source line). The "≥ 2 sentences" rule captures the actual intent: distinguish narrative prose from terse commands. A single source line with three sentences is prose; a multi-source-line bullet point that happens to have soft-wraps is not.

Track `preceding_heading` for each paragraph — the nearest `^#+ ` line above it (or empty string).

## Finding classes (v2)

Each finding must declare a `finding_class` (REQUIRED — missing → validator drops the finding + counts toward budget):

| Class | Detector | Ratio gate |
|---|---|---|
| `paragraph` | Whole-paragraph rewrite below ratio 0.8 (G7 baseline) | Subject to ratio gate (skip if ≥ 0.8) |
| `lexical` | ≥ 1 hit from B1/B2/B3/B4/B5 wordlists in the paragraph | **Bypasses ratio gate** — emit even if paragraph ratio ≥ 0.8 |
| `meta` | Line-leading meta self-reference marker (A4) | **Bypasses ratio gate** — deletes the meta sentence(s) only; fact-bearing remainder survives |
| `hedge` | Decision-layer hedge token (E4) in first paragraph / `## TL;DR` / `## Summary` | **Bypasses ratio gate** — emit hedge sentence + rewrite |

A paragraph can match multiple classes; emit **one finding per class per paragraph** (a paragraph with 3 weasel words AND a meta marker → 2 findings: one `lexical`, one `meta`).

## Output schema (strict YAML)

Reply with **YAML only**, no surrounding prose, matching:

```yaml
file: "<absolute path of target file>"
findings:
  - lines: "L<start_line>-L<end_line>"
    finding_class: <"paragraph" | "lexical" | "meta" | "hedge">   # REQUIRED (v2)
    semantic_axis: G7                                              # REQUIRED when finding_class == "paragraph"; OMIT for lexical / meta / hedge (task-2)
    preceding_heading: "<text of nearest heading above, or empty string>"
    original_words: <int, CJK-aware token count (see §Rules); the validator recounts>
    rewritten_words: <int, same CJK-aware counter applied to rewritten_text>
    ratio: <float, rewritten_words / original_words, 2 dp>
    confidence: <"high" | "medium" | "low">
    rationale_bucket: <true | false>   # true if preceding_heading matches the suppression set below
    lexical_hits:                       # REQUIRED when finding_class == "lexical"; omit otherwise
      - {token: "<matched token>", subclass: "<B1|B2|B3|B4|B5>"}
      - ...
    evidence_quote: |
      <literal substring per class rules below:
       - paragraph: at least one full sentence, typically a redundant or narrative sentence you removed
       - lexical: the sentence containing the first lexical hit
       - meta: the line-leading meta sentence(s) you are removing
       - hedge: the hedge sentence within the decision-layer scope>
    rewritten_text: |
      <the compressed paragraph; may span multiple lines.
       For meta class: the paragraph with its leading meta sentence(s) removed —
       non-empty when a fact-bearing remainder exists, empty only when the whole
       paragraph was meta.>
    suggested_action: <one short sentence on how to apply the rewrite>
  - ...
summary:
  total_paragraphs_scanned: <int>
  flagged_below_0_8: <int>
  high_severity_below_0_5: <int>
  findings_by_class:                  # REQUIRED (v2)
    paragraph: <int>
    lexical: <int>
    meta: <int>
    hedge: <int>
  note: <optional string — e.g. "input appears to be slide deck, returning empty per scope">
```

**Required field reminders**:

- `finding_class` is **REQUIRED for v2** on every finding. Missing or unknown value → validator drops + counts toward budget. No silent defaulting on the agent path.
- `lexical_hits` is **REQUIRED when `finding_class == "lexical"`**. Missing → validator drops + counts toward budget. Omit (or empty array) for other classes.
- `semantic_axis: G7` is **REQUIRED when `finding_class == "paragraph"`**, and MUST be omitted for `lexical` / `meta` / `hedge`. Missing on a paragraph finding → drop; present on a non-paragraph finding → drop. Both count toward the relative drop budget.
- `findings_by_class` in summary is **REQUIRED for v2** — count of findings per class.

The `semantic_axis: G7` field on paragraph-class findings marks them as the post-2026-05-29 successor of the (removed) `skill-semantic-audit --axis G7` output. Downstream consumers (e.g. flow-dev spec bridging) should treat this field as the grep-friendly token replacing the old `axis == "G7"` parse. The field is intentionally paragraph-class-only — `lexical` / `meta` / `hedge` are prose-guidelines-native classes with no semantic-audit equivalent, so setting `semantic_axis` on them is a schema error.

## Suppression set (`rationale_bucket: true` when matched)

Mark a finding `rationale_bucket: true` if `preceding_heading` (case-insensitive substring match on any token) contains any of:

```
why | rationale | background | 為什麼 | 背景 | 理由 |
tutorial | walkthrough | overview | introduction | 教學 |
references | see also | further reading | notes
```

The main agent uses this flag to downgrade severity one level (HIGH → MED, MED → LOW, LOW → suppressed). Do NOT downgrade yourself in your output — report the raw ratio + severity, let the orchestrator apply the rule.

**E4-only suppression extension** (decision-layer hedge): the following four tokens additionally suppress `finding_class: hedge` findings but **do not** apply to general paragraph compression:

```
risks | assumptions | 風險 | 假設
```

Rationale: authors legitimately hedge inside `## Risks` / `## Assumptions` sections — that's where uncertainty belongs. Suppress hedge findings under those headings only. Do not extend this carve-out to paragraph/lexical/meta classes.

## Severity rules (you self-report; main agent re-verifies)

**Paragraph class** (ratio-based, unchanged from v1 / G7):

| Ratio | Confidence to set |
|---|---|
| < 0.5 | `high` (only if you are sure every fact preserved) |
| 0.5–0.7 | `medium` |
| 0.7–0.8 | `low` |
| ≥ 0.8 | DO NOT include in findings (skip the paragraph) |

If you cannot compress a paragraph below 0.8 without losing content, **skip it** — do not emit a no-op finding. The summary's `total_paragraphs_scanned` still counts it; only `flagged_below_0_8` and findings entries omit it.

**Lexical / meta / hedge classes** (hits-based, **ratio gate bypassed**):

| Class | Hit count in paragraph | Confidence to set |
|---|---|---|
| `lexical` | ≥ 3 wordlist hits | `high` |
| `lexical` | 2 wordlist hits | `medium` |
| `lexical` | 1 wordlist hit | `low` |
| `meta` | line-leading meta marker present | `high` |
| `hedge` | ≥ 1 hedge token in decision-layer scope | `medium` |

A one-word swap (`leverage → use`) is a legitimate compression even when the paragraph-level ratio stays ~0.95 — that is exactly why lexical/meta/hedge bypass the 0.8 ratio gate. Emit the finding; the main agent decides whether to surface it based on severity sub-table B in `SKILL.md`.

## Lexical antipatterns — English (B1)

Flag the paragraph as `finding_class: lexical` if it contains ≥ 1 of these 15 English weasel words (case-insensitive, whole-word match):

```
leverage | various | robust | facilitate | appropriate |
comprehensive | holistic | seamless | streamline | sufficient |
adequate | relevant | reasonable | proper | utilize
```

For each hit, record an object `{token: "<exact matched token, case-preserved>", subclass: "B1"}` in `lexical_hits`. In `rewritten_text`, replace with a concrete verb / quantity or delete:

- `leverage X → use X` (or name the specific mechanism)
- `various Y → list Y or give a count` (`various tools` → `git, jq, fzf`)
- `robust → name the specific guarantee` (`robust retry` → `retries 3x with exponential backoff`)
- `facilitate → enable / do directly`
- `utilize → use`

**Adjacent-quantification skip rule** (false-positive guard): if the weasel word is **immediately adjacent** to a numeric / quantitative token, do **not** flag it. Examples that must NOT flag:

- `leverages a 10k-entry LRU cache` — `leverage` is doing real work next to a quantity
- `various 256-bit keys` — `various` is paired with a measurable count

The agent must look for adjacent digits, units (`MB / GB / ms / req/s`), or explicit counts within ±3 tokens of the weasel word.

**Example before/after**:

> **Before** (ratio 0.95, would pass v1): `We leverage various robust mechanisms to facilitate appropriate handling of user requests.` (12 words, 4 hits)
>
> **After** (lexical class, rewritten_text): `We retry user requests 3x with exponential backoff.` (8 words; 4 hits → confidence high)
>
> `lexical_hits`: `[{token: leverage, subclass: B1}, {token: various, subclass: B1}, {token: robust, subclass: B1}, {token: facilitate, subclass: B1}]` — note `appropriate` is also B1 but the validator dedups by surface token, and severity is per-sub-class (4× B1 → HIGH; see §Rules + SKILL.md sub-table B).

## Lexical antipatterns — Chinese (B2)

Flag the paragraph as `finding_class: lexical` if it contains ≥ 1 of these 11 Chinese weasel words:

```
進行 | 實施 | 相關的 | 一定程度上 | 某種程度上 |
相對來說 | 基本上 | 大致上 | 所謂的 |
有關的 | 針對性的
```

(`其實` is **not** in B2 — it is an intensifier owned by B4. A token belongs to exactly one sub-class, so dedup is structural: a paragraph's lone `其實` counts as one B4 hit, never double-counted across B2+B4.)

**Prompt-internal rewrite hint** (applied directly to `rewritten_text`; no new YAML output field):

```
進行 X 的 Y  →  Y X
```

Examples:

- `進行系統的分析` → `分析系統`
- `進行相關的測試` → `測試`
- `實施有效的監控` → `監控`
- `基本上來說，這個方案是可行的` → `這個方案可行`

For each hit, record an object `{token: "<exact matched token>", subclass: "B2"}` in `lexical_hits`.

## Nominalization → verb (B3)

Flag the paragraph as `finding_class: lexical` if it contains a "verb-noun pair" where the noun is a nominalized verb. Replace with the active verb form.

**English mappings**:

| Before | After |
|---|---|
| make a decision | decide |
| perform an analysis | analyze |
| conduct a review | review |
| carry out an investigation | investigate |
| provide assistance | assist / help |
| reach a conclusion | conclude |
| have a discussion | discuss |

**Chinese mappings**:

| Before | After |
|---|---|
| 進行分析 | 分析 |
| 做出決策 | 決定 |
| 提供協助 | 協助 |
| 進行檢查 | 檢查 |
| 進行討論 | 討論 |

Record the matched verb-noun phrase as `{token: "<whole phrase>", subclass: "B3"}` in `lexical_hits` (the whole phrase, e.g. `make a decision`, not just `make`).

## Empty intensifier strip (B4)

Flag the paragraph as `finding_class: lexical` if it contains ≥ 1 of these intensifier tokens. In `rewritten_text`, **delete the intensifier** unless it's load-bearing for accuracy.

**English**:

```
very | really | quite | actually | basically |
simply | literally | essentially | just
```

(`just` is drawn from the caveman skill's filler drop-list — an empty intensifier in the same family as `simply` / `basically`.)

**Chinese**:

```
非常 | 真的 | 其實 | 根本 | 顯然 | 相當 | 極為
```

**Context exceptions** (do NOT flag — intensifier is load-bearing):

- Release-note tone where the intensifier signals user-facing emphasis (`This is a very breaking change`)
- Direct quotation of user input or external source
- Comparative context where the intensifier carries meaning (`basically the same as v1` — `basically` is hedging an equivalence claim, leave it)

For each hit, record an object `{token: "<exact matched token>", subclass: "B4"}` in `lexical_hits`.

## Redundant phrase + doubled word (B5)

Flag the paragraph as `finding_class: lexical` if it contains ≥ 1 redundant multi-word phrase or an adjacent duplicate word. In `rewritten_text`, **replace the phrase with its short form** / **delete the doubled word**. This is principle 1 ("cut what does no work") — a deterministic substitution, near-zero false positive.

**Redundant-phrase swap table** (replace left → right):

```
in order to            → to
due to the fact that   → because
at this point in time  → now
in the event that      → if
for the purpose of     → for
in spite of the fact   → although
a large number of      → many
at the present time    → now
in the process of      → (delete; use the bare verb)
has the ability to     → can
```

**Adjacent duplicate word**: two identical words in a row (`the the`, `is is`, `to to`) — delete the second. Case-insensitive; do not flag a deliberate doubled word inside a quotation.

For each hit, record an object `{token: "<exact matched phrase or doubled word>", subclass: "B5"}` in `lexical_hits`.

**Sub-class precedence (B5 vs contained B1/B4 token).** A redundant-phrase span may contain an existing-class token (`basically in order to` holds B4 `basically` inside a B5 phrase). Rule: **the longest matching span wins, and a token belongs to exactly one sub-class by that span.** A B5 phrase claims its whole span; a B1/B4 token only *inside* that span is not separately recorded — this preserves the one-sub-class-per-token + dedup invariant the severity recount depends on.

**Fact-token survival**: like every lexical class, a B5 rewrite is subject to Gate 7 — if a redundant phrase abuts a fact token (`in order to 429`), the substitution must keep `429` (`to 429`), or the finding drops.

## Meta self-reference (A4)

Flag the paragraph as `finding_class: meta` if its **first non-blank line** starts with (case-insensitive) any of:

**English regex patterns**:

```
^This (document|section|page|skill|file) (describes|explains|covers|outlines)
^The (following|next) (section|paragraph) (will|shall)
^In this (document|section|chapter)
^Below (we|you will find|is)
```

**Chinese regex patterns**:

```
^本文(將|要)?(介紹|描述|說明|涵蓋)
^以下(將|會)?(描述|介紹|說明)
^本(章節|節|文件|頁)(描述|說明)
^接下來(將|會)?(介紹|描述)
```

**Rule: delete the meta sentence(s) only — never the fact-bearing remainder.** A meta self-reference *sentence* is redundant with its surrounding structure — the reader already knows what section they're in. But the rest of the paragraph may carry real technical content (numbers, named entities, branches). Delete the leading meta sentence(s); keep everything else verbatim. Emit:

- `evidence_quote`: the line-leading meta sentence(s) you are removing (one or more full sentences from the start of the paragraph)
- `rewritten_text`: the paragraph **with its leading meta sentence(s) removed** — non-empty when a fact-bearing remainder exists, empty only when the whole paragraph was meta. Copy the surviving sentences verbatim.
- `confidence`: `high`
- `suggested_action`: `Delete the meta sentence(s); keep the remaining content`

Example — `This section describes the pipeline. The flow has 3 stages reporting to Prometheus.` → `rewritten_text`: `The flow has 3 stages reporting to Prometheus.` (the second sentence survives verbatim; `3` and `Prometheus` are preserved). `rewritten_words` / `ratio` are computed on the surviving remainder per the §Rules counter — they are real values, not `0`.

## Decision-layer hedge (E4)

Flag the paragraph as `finding_class: hedge` if it contains ≥ 1 hedge token **AND** is in the decision-layer scope.

**Hedge tokens**:

```
might | probably | we think | seems | appears | 可能 | 或許 | 大概
```

**Decision-layer scope** (E4 only applies inside these locations):

- **First paragraph of the document** (before any `##` heading) — typically a TL;DR / lead paragraph
- Paragraph directly under `## TL;DR` heading
- Paragraph directly under `## Summary` heading
- For Jira specs: first paragraph of the description field

**Out-of-scope** (E4 suppression set extension — do NOT flag hedges here):

- Paragraph directly under `## Risks` heading
- Paragraph directly under `## Assumptions` heading
- Paragraph directly under `## 風險` heading
- Paragraph directly under `## 假設` heading

Rationale: authors legitimately hedge in Risks / Assumptions sections — that's where uncertainty belongs. The hedge ban targets decision-layer claims (`we think this might possibly work` at the top of a spec) where hedging undermines reader trust.

For hedge findings:

- `evidence_quote`: the hedge sentence within the decision-layer scope
- `rewritten_text`: rewrite removing the hedge (`we think might possibly work` → `works` or `unverified — see Risks`)
- `lexical_hits`: omit (hedge class does not populate `lexical_hits`; the hedge tokens are recorded in `evidence_quote`)
- `confidence`: `medium`

## Rules

- `lines` must be exact line numbers of the original paragraph in the source file
- `evidence_quote` must be a **literal substring** of the paragraph as it appears in the file — copy characters, do not paraphrase
- `original_words` and `rewritten_words` must be exact counts from the **CJK-aware tokenizer** below — NOT a plain whitespace split (whitespace split is wrong for CJK: a spaceless Chinese sentence collapses to one token, making `ratio` meaningless). Count latin runs as one token each, and each CJK ideograph as one token:

  ```python
  count = len(re.findall(r"[A-Za-z0-9]+(?:[.\-/][A-Za-z0-9]+)*|[一-鿿]", text))
  ```

  The **validator script recounts** `original_words` / `rewritten_words` / `ratio` with this exact counter (Gate 8) and drops the finding if your self-report diverges by > 0.05 — so match it. For a paragraph-class finding, a recount `ratio ≥ 0.8` is also dropped (the skip rule, now mechanically enforced).
- `ratio` rounded to 2 dp
- `finding_class` is REQUIRED on every finding; missing → validator drops + counts toward budget
- `lexical_hits` is REQUIRED when `finding_class == "lexical"`; each entry is a `{token, subclass}` object (subclass ∈ B1/B2/B3/B4/B5); missing → validator drops + counts toward budget
- `semantic_axis: G7` is REQUIRED when `finding_class == "paragraph"` and MUST be omitted for other classes; mismatched → validator drops + counts toward budget
- If detecting the file is out-of-scope (slide deck, blog, essay), emit empty findings + summary note; do NOT attempt compression with the SKILL.md rubric

## Hallucination guards (validator-enforced)

The main agent runs `scripts/validate-findings.sh` after you reply. The script enforces:

1. **`lines` in bounds** — start ≥ 1, end ≤ file_line_count, start ≤ end
2. **`evidence_quote` is literal substring** — the script does `grep -F <evidence_quote> <file>` (or equivalent); non-match → finding dropped
3. **`finding_class` presence + value** — missing or not in `{paragraph, lexical, meta, hedge}` → finding dropped
4. **`lexical_hits` presence when class is lexical** — missing/empty → finding dropped
5. **`semantic_axis` presence/absence (task-2)** — paragraph-class finding missing `semantic_axis: G7` → dropped; non-paragraph-class finding with `semantic_axis` set → dropped
6. **Gate 7 — fact-token preservation** (non-`meta` only): the validator extracts a closed set of hard fact tokens (numbers+units incl. hyphen-units like `15-minute`, ranges/codes like `5xx` / `30-50%` / HTTP `429`, paths, `--flags`, errno, header-idents like `Retry-After`, hex/SHA, IP, and CJK/latin negation words matched by **substring** — `不` / `除非` / `否則` / `not` / `unless`) from the cited original range and requires every one to survive in your `rewritten_text`. A missing fact token → finding dropped. **Lexical exemption**: tokens that fall inside a recorded `lexical_hits` span are excluded first, so deleting a flagged weasel never trips the gate — but dropping an *unflagged* number / errno / path / negation does. `meta` is exempt (its rewrite is sentence-level, keeping any fact-bearing remainder).
7. **Gate 8 — CJK-aware ratio recount**: the validator recomputes `original_words` / `rewritten_words` / `ratio` with the CJK-aware counter (see §Rules) and drops the finding if your self-reported `ratio` diverges by > 0.05, or if a paragraph-class recount `ratio ≥ 0.8` (the skip rule, mechanically enforced).
8. **Relative drop budget**: `budget = max(3, ceil(0.15 * len(findings)))`. If drops ≥ budget, the **entire batch is invalidated** and the main agent surfaces an error. Treat every `evidence_quote` and `finding_class` as if it will be machine-checked, because it will.

Your `confidence` field is advisory; the validator is binding. A confident finding that fails validation is dropped.

**Gate 7 rationale (design basis: caveman Auto-Clarity).** Gate 7 exists because the one thing that lands in the file — `rewritten_text` — was previously the one thing no gate read. Its design follows the `caveman` skill's **Auto-Clarity** principle: *stop compressing when compression itself creates technical ambiguity — order, omitted conjunctions, condition branches*. A rewrite that silently drops `3 retries`, flips `100ms`→`10ms`, or deletes an `ECONNREFUSED → no retry` branch is exactly that ambiguity, so Gate 7 blocks it by requiring the hard fact tokens to survive. caveman's `drop articles` / `[thing][action][reason]` telegraph style is **not** adopted here — it violates prose-guidelines's scope boundary (`SKILL.md` scope: stylistic rhythm trumps compression); only the Auto-Clarity stop-rule is borrowed.

## Worked examples

Refer to `skill-audit/references/llm-prompts/g7-prompt.md` "Few-shot examples" section. The three examples there (HIGH compression / MED compression / no-op) apply verbatim **to the paragraph class**. The only difference: this prompt expects you to emit them as **list items inside `findings:`**, not as a single top-level YAML object.

The class-specific sections above (B1/B2/B3/B4/B5/A4/E4) include their own before/after examples that augment — and do not replace — the G7 baseline.

## Out-of-scope detection (return early)

If, after reading the file, you determine it is:

- A **slide deck** (most content is `- bullet items` under heading-style slide titles, very little prose paragraph)
- A **blog post or essay** (narrative voice, first/second person, stylistic looseness)
- A **README marketing-style doc** (heavy on tagline / value-prop prose, not technical detail)

→ emit:

```yaml
file: "<path>"
findings: []
summary:
  total_paragraphs_scanned: 0
  flagged_below_0_8: 0
  high_severity_below_0_5: 0
  findings_by_class:
    paragraph: 0
    lexical: 0
    meta: 0
    hedge: 0
  note: "Out of scope — detected <doc-type>. prose-guidelines targets SKILL.md and engineering specs only. Use a different tool for this content."
```

This is not failure — it's a correct scope refusal.
