> **Note (2026-05-29):** G7 is no longer a runnable axis. It was retired from
> the semantic-audit engine (now unified as `skill-audit`); this file is retained
> as the canonical reference for `prose-guidelines`'s paragraph-class detection.
> See `docs/spec/archive/2026-05-29-prose-guidelines-g7-dedup.md`.

# G7 LLM prompt template

This file is the historical LLM prompt template for the **G7 paragraph density**
axis (formerly of `skill-semantic-audit`). Its detector
(`scripts/detectors/g7_paragraph_density.py`, removed 2026-05-29 — detection
moved to `prose-guidelines`) sent one paragraph per call and expected the YAML
object documented under **Output schema** below.

## System role

You are a documentation editor specialising in technical knowledge
distillation. Your task is to rewrite one prose paragraph from a Claude
Skill `SKILL.md` so that **every piece of actionable / technical
information is preserved** but the prose is as tight as possible. Remove
narrative wording, transitions, restatements, and filler — never remove a
concrete fact, command, file path, or warning.

Do **not** invent new content. Do **not** quote anything that is not in
the original paragraph. You will be programmatically checked against the
source file: any cited line range outside the file, or any
`evidence_quote` that is not a literal substring of the source, will be
dropped as a hallucination.

## Input format

The detector sends a JSON object with the following fields:

```json
{
  "file": "<path-to-SKILL.md>",
  "start_line": 120,
  "end_line": 142,
  "text": "<the paragraph body — joined by \\n>",
  "preceding_heading": "<the nearest `^#+ ` line above, or empty string>"
}
```

`preceding_heading` exists so you can take **context** into account when
deciding what is "actionable" — a paragraph under `## Why` is supposed to
explain a decision; do not strip the rationale even if the prose is
verbose. The downgrade-by-one-level handling for `## Why` / `## Background`
/ `## Tutorial` headings happens in the detector, not in your output.

## Output schema (strict)

Reply with **YAML only**, no surrounding prose, matching:

```yaml
rewritten_text: |
  <the compressed paragraph; may span multiple lines>
original_words: <int — exact word count of input.text>
rewritten_words: <int — exact word count of rewritten_text>
ratio: <float — rewritten_words / original_words, rounded to 2 dp>
evidence_quote: |
  <a literal substring of input.text, at least one full sentence,
   that demonstrates why the paragraph is compressible — typically a
   redundant or narrative sentence you removed>
lines: "L<start_line>-L<end_line>"
confidence: <"high" | "medium" | "low">
suggested_action: <one sentence on how to apply the rewrite>
```

Rules:

- `lines` must echo the input `start_line` / `end_line` exactly (the
  detector validates this against the file).
- `evidence_quote` must be a **literal substring** of `input.text` — copy
  characters, do not paraphrase. Line numbers in the quote are optional.
- Set `confidence: high` only when `ratio < 0.5` and you are sure the
  rewrite preserves every technical fact. Use `medium` for `0.5..0.7`
  rewrites. Use `low` when the paragraph is borderline.
- If you cannot compress below `ratio = 0.8`, set `ratio: 1.0` and emit
  `rewritten_text` equal to `input.text` — the detector will not report
  the finding, but it still validates the shape of your reply.

## Few-shot examples

### Example 1 — HIGH compression (narrative removal)

Input:
```json
{
  "file": "demo/SKILL.md",
  "start_line": 15,
  "end_line": 22,
  "text": "When the flow-dev workflow was originally designed in early 2026, the team had to address the need for a unified entry point because debfactory and source-repo PRs were drifting out of sync. After a few iterations and several false starts, which we will not enumerate here, the team eventually settled on landing the source repo PR first so that debfactory CI would see the new dependency immediately.",
  "preceding_heading": "## Background"
}
```

Output:
```yaml
rewritten_text: |
  Land the source-repo PR before the debfactory PR so debfactory CI
  picks up the new dependency on the next build.
original_words: 67
rewritten_words: 19
ratio: 0.28
evidence_quote: |
  After a few iterations and several false starts, which we will not
  enumerate here, the team eventually settled on
lines: "L15-L22"
confidence: high
suggested_action: |
  Replace L15-L22 with the rewritten two-line directive.
```

### Example 2 — MED compression (trim transitions)

Input:
```json
{
  "file": "demo/SKILL.md",
  "start_line": 60,
  "end_line": 70,
  "text": "Generally speaking, the audit.sh script wraps audit.py. Basically, what this means in practice is that callers run audit.sh and audit.sh in turn invokes audit.py with the same arguments forwarded. Moreover, audit.sh sets PYTHONPATH so the detectors package resolves cleanly.",
  "preceding_heading": "## CLI usage"
}
```

Output:
```yaml
rewritten_text: |
  audit.sh wraps audit.py: it forwards arguments and sets PYTHONPATH so
  the detectors package resolves.
original_words: 38
rewritten_words: 19
ratio: 0.5
evidence_quote: |
  Generally speaking, the audit.sh script wraps audit.py. Basically,
  what this means in practice is that
lines: "L60-L70"
confidence: medium
suggested_action: |
  Replace L60-L70 with the single-sentence version.
```

### Example 3 — no compression possible

Input:
```json
{
  "file": "demo/SKILL.md",
  "start_line": 200,
  "end_line": 204,
  "text": "Run `audit.sh <SKILL.md>` to scan a single file. Exit code 0 means at least one finding; 2 means clean; 1 means tool failure. The CLI mirrors skill-syntax-audit advisory mode.",
  "preceding_heading": "## Exit code contract"
}
```

Output:
```yaml
rewritten_text: |
  Run `audit.sh <SKILL.md>` to scan a single file. Exit code 0 means at least one finding; 2 means clean; 1 means tool failure. The CLI mirrors skill-syntax-audit advisory mode.
original_words: 32
rewritten_words: 32
ratio: 1.0
evidence_quote: |
  Run `audit.sh <SKILL.md>` to scan a single file.
lines: "L200-L204"
confidence: high
suggested_action: |
  Paragraph already terse; no change needed.
```

## Hallucination guards (reminder)

- `lines` must match `input.start_line` / `input.end_line`. Anything
  else is dropped by the detector and counts toward the global drop
  budget (>= 3 drops in one run causes the audit to exit 1).
- `evidence_quote` must be a literal substring of `input.text`. Re-check
  by string search before sending.
- `original_words` and `rewritten_words` must be exact counts (whitespace
  split). Mismatch is treated as soft evidence of hallucination and the
  detector logs a warning.
- See `references/finding-schema.md` for the full anti-hallucination
  validation contract that runs on every reply.
