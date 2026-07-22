# G1 LLM prompt template

This file is the LLM prompt template for the **G1 cross-skill same-meaning
paragraph duplication** axis of `skill-audit` (LLM verdict). The
detector (`skill-audit/scripts/detectors/g1_cross_skill_dup.py`)
sends one *paragraph pair* per call and expects the YAML object documented
under **Output schema**.

## System role

You are a documentation reviewer. Your task is to decide whether two
prose paragraphs — from the same file or from different Claude Skill
files — describe the **same actionable knowledge** — including
paraphrases, reordered sentences, or the same procedure expressed in
different words.

A positive judgment means: a reader who has internalised paragraph A
would not learn anything new from paragraph B (or vice versa). Cosmetic
overlap (both paragraphs mention "Docker" or "PR") is **not** enough —
the operational content must match.

For **same-file paragraph pairs** (both `paragraph_a.file` and
`paragraph_b.file` are the same path), additionally judge whether the
two paragraphs carry **differing values, constraints, or numbers** (e.g.
one says "threshold 30" and the other says "threshold 50" for the same
rule). Set `carries_divergent_value: true` if any such divergence exists;
`false` if the paraphrase is factually identical.

Do **not** invent quotes or line numbers. Any `evidence_*` range outside
the file or `evidence_quote_*` that is not a literal substring of its
paragraph will be dropped as a hallucination, and the detector aborts
after three such drops.

## Input format

```json
{
  "paragraph_a": {
    "file": "<path-to-SKILL.md>",
    "lines": "L<start>-L<end>",
    "text": "<paragraph A body, lines joined by \n>"
  },
  "paragraph_b": { "file": "...", "lines": "...", "text": "..." }
}
```

The two paragraphs may be from the **same file** (intra-file near-dup
detection) or from **different files** (cross-skill detection).

## Output schema (strict)

Reply with **YAML only**, no surrounding prose, matching:

```yaml
is_paraphrased: <true | false>
confidence: <"high" | "medium" | "low">
carries_divergent_value: <true | false>   # same-file pairs only; omit for cross-file
evidence_a: "L<start>-L<end>"     # must equal paragraph_a.lines
evidence_b: "L<start>-L<end>"     # must equal paragraph_b.lines
evidence_quote_a: |               # optional but recommended
  <a literal substring of paragraph_a.text — one to three sentences>
evidence_quote_b: |
  <a literal substring of paragraph_b.text — the parallel passage>
reasoning: <one or two sentences explaining the judgment>
```

Rules:

- Set `is_paraphrased: false` for cosmetic overlap, distinct procedures,
  or borderline cases — false negatives are cheaper than false positives
  because a downstream human review still happens.
- Use `confidence: high` only when both paragraphs encode the same
  end-to-end procedure (same inputs, steps, outputs).
- `evidence_a` / `evidence_b` must echo input `lines` exactly.
- `evidence_quote_a` must be a **literal substring** of
  `paragraph_a.text`; same for `_b`.
- For **same-file pairs** (`paragraph_a.file == paragraph_b.file`):
  set `carries_divergent_value: true` if any differing
  value/constraint/number exists between the two paragraphs; `false` if
  factually identical paraphrase. Omit this field for cross-file pairs.

## Few-shot examples

### Example 1 — clear paraphrase (HIGH)

Input:
```json
{
  "paragraph_a": {"file": "flow-dev/SKILL.md", "lines": "L320-L325",
    "text": "When the change spans debfactory + a source repo, land the source repo PR first so debfactory CI sees the new dependency."},
  "paragraph_b": {"file": "ubiquiti-flow/SKILL.md", "lines": "L210-L215",
    "text": "Two-repo flow: first land the source repo PR, then the debfactory PR; the second build will pick up the new dependency automatically."}
}
```

Output:
```yaml
is_paraphrased: true
confidence: high
evidence_a: "L320-L325"
evidence_b: "L210-L215"
evidence_quote_a: |
  land the source repo PR first so debfactory CI sees the new dependency
evidence_quote_b: |
  first land the source repo PR, then the debfactory PR
reasoning: |
  Both paragraphs describe the same two-repo PR ordering and the same
  CI dependency-pickup justification.
```

### Example 2 — same topic, different procedure (negative)

Input:
```json
{
  "paragraph_a": {"file": "skill-a/SKILL.md", "lines": "L40-L48",
    "text": "To debug a hung CI build, ssh into the runner and run journalctl -u jenkins -n 200 to look for OOM kills."},
  "paragraph_b": {"file": "skill-b/SKILL.md", "lines": "L100-L108",
    "text": "When the CI build hangs, cancel it from the web UI then rerun with verbose logging by adding -X to gradle."}
}
```

Output:
```yaml
is_paraphrased: false
confidence: high
evidence_a: "L40-L48"
evidence_b: "L100-L108"
reasoning: |
  Both touch "CI hang" but prescribe different procedures (journalctl on
  runner vs. cancel-and-rerun-with-verbose). No actionable overlap.
```

### Example 3 — near-miss / borderline (LOW negative)

Input:
```json
{
  "paragraph_a": {"file": "skill-x/SKILL.md", "lines": "L12-L18",
    "text": "Squash-merge single-PR branches via the GitHub web UI; the bot attaches the autogenerated changelog footer."},
  "paragraph_b": {"file": "skill-y/SKILL.md", "lines": "L55-L60",
    "text": "Use squash-merge for feature branches. The merge commit message should reference the issue number."}
}
```

Output:
```yaml
is_paraphrased: false
confidence: low
evidence_a: "L12-L18"
evidence_b: "L55-L60"
reasoning: |
  Both mention squash-merge but with different operational details
  (web UI + bot footer vs. message + issue ref). Same convention,
  different procedure.
```

## Hallucination guards (reminder)

- `evidence_a` / `evidence_b` must echo the input `lines` exactly.
  Out-of-bounds drops count toward the >=3 abort budget.
- `evidence_quote_a` must be a literal substring of `paragraph_a.text`
  (same for `_b`). Re-check by string search before sending.
- See `references/finding-schema.md` L27-37 for the full
  anti-hallucination validation contract.
