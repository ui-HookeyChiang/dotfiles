# Finding schema

Every finding emitted by `skill-audit` (axes G1 / G8; G7 moved to prose-guidelines) conforms to this YAML schema. Findings stream to stdout as a YAML list under the top-level key `findings:`.

## Required fields

| Field | Type | Notes |
|---|---|---|
| `id` | string | Stable per-run id, format `g{axis}-NNN` (e.g. `g1-001`, `g8-012`). |
| `axis` | enum | `G1` \| `G8`. |
| `severity` | enum | `HIGH` \| `MED` \| `LOW`. See `severity-rubric.md`. |
| `confidence` | enum | `high` \| `medium` \| `low`. LLM self-assessment (Q2-A single-shot + structured confidence). |
| `title` | string | One-line human summary. |
| `summary` | string | 1-3 sentences describing the issue and the recommended direction. |
| `locations` | list | One or more `{file, lines}` records. `lines` is a string range like `"L320-L355"`. |
| `evidence_quote` | string (block) | **Mandatory.** Literal quote from each location with line numbers. The anti-hallucination validator (see below) checks the cited range exists in the file. |
| `suggested_action` | string | Free-text recommendation. MVP does not constrain into a closed enum. |
| `requires_human` | bool | **MVP: always `true`.** Reserved for v0.2 auto path. |

## Conditional fields

| Field | Required when | Type | Notes |
|---|---|---|---|
| `numeric_basis` | `axis in (G1, G8)` | null | Explicit `null` for schema uniformity. G7 emits no findings here — moved to prose-guidelines. |
| `disposition` | `axis == G1` AND intra-file finding | string | `merge` — paraphrase with no divergent values; safe to consolidate. `divergent-hazard` — paraphrase but carries differing values/constraints/numbers; do NOT merge without human review. Absent (null) for cross-file G1 findings. Default-conservative: missing or uncertain `carries_divergent_value` from LLM → `divergent-hazard`. |

## Anti-hallucination — line-number validation contract

The CLI (`scripts/audit.py` shim → `scripts/syntax_audit.py`, lands in a separate task) **must** validate every `evidence_quote` before writing the finding to stdout:

1. Parse each `locations[].lines` value (format `"Lstart-Lend"`).
2. Open the referenced `file` and count its lines.
3. If `start < 1` or `end > total_lines`, the line range is **out of bounds**.
4. Out-of-bounds findings are **silently dropped from stdout** (they never reach the user) and a counter on stderr increments.
5. If `≥ 3` findings are dropped for line-range violations in a single run, the tool exits with code `1` and emits a stderr summary. Rationale: a hallucination rate this high makes the run untrustworthy as a whole, and `exit 1` matches the `skill-syntax-audit` advisory-mode "LLM failure" contract.

This is **complementary** to the `confidence` self-assessment field. `confidence` is what the LLM claims about its own finding; line-number validation is a hard check the code always performs, regardless of `confidence`.

## Example — HIGH G1 finding (cross-skill duplicate)

```yaml
findings:
  - id: g1-001
    axis: G1
    severity: HIGH
    confidence: high
    title: "flow-dev and ubiquiti-flow both describe the two-repo debfactory flow"
    summary: |
      Two skills carry paraphrased same-meaning paragraphs covering the
      "land source repo PR first, then debfactory PR" sequence. Recommend
      extracting to _shared/two-repo-debfactory.md and replacing both with
      cross-links.
    locations:
      - file: flow-dev/SKILL.md
        lines: "L320-L355"
      - file: ubiquiti-flow/SKILL.md
        lines: "L210-L248"
    evidence_quote: |
      flow-dev/SKILL.md L320-L325:
        "When the change spans debfactory + a source repo, land the source
         repo PR first so debfactory CI sees the new dependency."
      ubiquiti-flow/SKILL.md L210-L215:
        "Two-repo flow: first land the source repo PR, then the debfactory
         PR; the second build will pick up the new dependency automatically."
    numeric_basis: null
    suggested_action: |
      Extract the flow description to _shared/two-repo-debfactory.md.
      Replace both call sites with a one-line link to the shared file.
    requires_human: true
```

> **G7 example removed.** G7 (paragraph density) was retired from this engine
> on 2026-05-29 and emits no findings under this schema (axis enum is
> `G1 | G8`). Paragraph-density rewriting moved to `prose-guidelines`; see
> `docs/spec/archive/2026-05-29-prose-guidelines-g7-dedup.md`.

## Schema versioning

This file documents schema **v0.1 (MVP)**. Future versions may relax `requires_human: true` to allow auto-executable findings; the field name is forward-compatible.
