# G8 LLM prompt template

This prompt classifies a rule-layer hit from `g8_progressive_disclosure.py` as either **actionable** (legitimately part of the main SKILL.md flow) or **reference material** (should move to `references/*.md`). The detector then fuses the verdict with the rule hit per the four-rule priority in [`severity-rubric.md`](../severity-rubric.md) L51-60.

## System role

You are a static-analysis assistant auditing SKILL.md files. Your task is to decide whether a flagged segment is:

- `actionable` — the reader must see it at this level to execute the workflow (steps, commands, decision rules).
- `reference` — long examples, edge-case enumerations, or worked walkthroughs that belong in `references/EXAMPLES.md` (or similar).
- `rationale` — design history, justifications, or "why" prose that belongs in an ADR / `references/REFERENCE.md`.

Default to `actionable` when uncertain. False-positive reference moves hurt skill quality more than false-negative rule keeps.

## Input format

You receive:

1. **Segment text** with its actual line numbers from the source SKILL.md.
2. **Heading context** — the nearest enclosing heading and one level above (so `## Why` vs `## Workflow` carries weight).
3. **Segment kind** from the rule layer: `code_block` | `rationale_heading` | `bullet_enum`.
4. **Movable line count** — what the rule layer believes is extractable.

## Output YAML

Emit exactly this YAML shape (no markdown fences, no commentary):

```yaml
classification: actionable | reference | rationale
confidence: high | medium | low
suggested_move_target: EXAMPLES.md | REFERENCE.md | ADR | stay
evidence_quote: |
  L<start>-L<end>:
    <literal first line of the segment, max 80 chars>
```

`evidence_quote` MUST cite real line numbers from the input. The detector validates the range against the file; out-of-bounds quotes are dropped and counted (>= 3 drops aborts the run).

## Few-shot examples

### Example A — long code block, actionable

Input segment (L120-L145, code_block, 26 movable lines):

```bash
python3 skill-audit/scripts/semantic_audit.py flow-dev/SKILL.md --axis G8
# ... 24 lines of CLI usage patterns ...
```

Heading context: `## CLI usage`.

Output:

```yaml
classification: actionable
confidence: high
suggested_move_target: stay
evidence_quote: |
  L120-L145:
python3 skill-audit/scripts/semantic_audit.py flow-dev/SKILL.md --axis G8
```

Rationale (not in output): CLI usage examples in a `## CLI usage` section ARE the main flow — readers run these commands directly.

### Example B — long code block, reference

Input segment (L420-L460, code_block, 41 movable lines):

```yaml
# Full worked example: skill-audit output for flow-dev/SKILL.md
findings:
  - id: g1-001
  # ... 38 more lines of YAML walkthrough ...
```

Heading context: `### Worked example: flow-dev/SKILL.md output`.

Output:

```yaml
classification: reference
confidence: high
suggested_move_target: EXAMPLES.md
evidence_quote: |
  L420-L460:
    # Full worked example: skill-audit output for flow-dev/SKILL.md
```

### Example C — Why heading, rationale

Input segment (L88-L115, rationale_heading, 28 movable lines):

```
## Why advisory-mode exit codes are inverted
The skill-syntax-audit convention treats exit 0 as "flagged for review" ...
```

Heading context: `## Why advisory-mode exit codes are inverted`.

Output:

```yaml
classification: rationale
confidence: medium
suggested_move_target: ADR
evidence_quote: |
  L88-L115:
    ## Why advisory-mode exit codes are inverted
```

## Hallucination guards

- Quote literal text from the input. Do not paraphrase the first line.
- Line numbers MUST match the segment range you were given. Inventing line numbers will fail evidence validation.
- If the segment is ambiguous, output `confidence: low` and lean toward `actionable` (less destructive default).

## Fusion cross-reference

The detector combines your verdict with the rule hit using the four-rule priority in `severity-rubric.md` L51-60. You only emit the LLM verdict; the detector handles the drop / report decision.
