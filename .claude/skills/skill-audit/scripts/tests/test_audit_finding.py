"""Tests for the AuditFinding model + per-engine output adapters.

Fixtures are REAL bytes captured 2026-06-19 from each engine run against
`flow-dev` (the dirty sample): deadcode via reachability.py, syntax via
audit.sh --no-spec, semantic via audit.py --no-llm.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from audit_finding import (  # noqa: E402
    AuditFinding,
    parse_deadcode,
    parse_syntax,
    parse_semantic,
)


def test_audit_finding_fields():
    f = AuditFinding(engine="syntax", code="R3", severity="HIGH",
                     location="L42-55", message="duplicated block")
    assert (f.engine, f.code, f.severity, f.location, f.message) == \
        ("syntax", "R3", "HIGH", "L42-55", "duplicated block")


# Re-captured after the reachability.py dynamic-path-invoker fix (this branch)
# + #847: 0 (c), 2 (e). KEEP rows suppressed below the table.
DEADCODE_REAL = """## Reachability findings

Skill: `flow-dev`  ·  findings: 2 (b/adv/KEEP suppressed below)

| Class | Severity | Kind | Name | Where | Note |
|---|---|---|---|---|---|
| (e) starved-artifact (advisory) | ADVISORY | artifact | `.docs-lifecycle.json` | `references/jira-phase4.md` | live readers, no resolvable writer — ADVISORY, verify external producer |
| (e) starved-artifact (advisory) | ADVISORY | artifact | `.questionnaire.locked` | `scripts/jira-phase4.sh` | live readers, no resolvable writer — ADVISORY, verify external producer |
| (KEEP) external-contract (KEEP) | — | field | `Drift` | `scripts/write-lock.sh:88` | external-contract (sibling/CI reads it) |
| (KEEP) external-contract (KEEP) | — | field | `Remediation` | `scripts/phase-0-preflight.sh:66` | external-contract (sibling/CI reads it) |
"""


def test_parse_deadcode_real_stacking_dev():
    out = parse_deadcode(DEADCODE_REAL)
    # only actionable cls c/d/e/f; the KEEP rows are dropped.
    assert len(out) == 2
    assert all(f.engine == "deadcode" for f in out)
    assert [f.code for f in out] == ["e", "e"]
    assert [f.severity for f in out] == ["ADVISORY", "ADVISORY"]
    assert out[0].location == "references/jira-phase4.md"
    assert out[1].location == "scripts/jira-phase4.sh"


def test_parse_deadcode_clean():
    clean = ("## Reachability findings\n\n"
             "No findings — every script / function / field is reachable.\n")
    assert parse_deadcode(clean) == []


# Real audit.sh --no-spec output on flow-dev (## Findings block verbatim).
SYNTAX_REAL = """# skill-syntax-audit report: stack-dev

**Target**: `flow-dev/SKILL.md`
**Total lines**: 950

## Bloat metrics

| Severity | Redundancy | Scriptifiable |
|---|---|---|
| HIGH | 0 | 0 |

## Findings

### F1 (MED) — stale Skill ref: `Skill brainstorming` not found in plugin oracle (~/.claude/skills/)

- Locations: lines 101-101
- Proposed refactor: either install the referenced skill, update the name if renamed, or drop the reference if obsolete

### S1 (LOW) — 4 chained bash commands with no human-judgement interjection

- Locations: lines 273-292
- Proposed refactor: Extract to `scripts/export-flow.sh` with appropriate arguments, replace block with `bash scripts/export-flow.sh ...`
- Estimated saved: 19 lines

### V1 (INFO) — unbound variable: $SPEC_PATH (referenced but never bound in-file)

- Locations: lines 143-143
- Proposed refactor: add a guard `: "${SPEC_PATH:?set by <X>}"` near the fence
"""


def test_parse_syntax_real_stacking_dev():
    out = parse_syntax(SYNTAX_REAL)
    assert [f.code for f in out] == ["F1", "S1", "V1"]
    assert all(f.engine == "syntax" for f in out)
    assert [f.severity for f in out] == ["MED", "LOW", "INFO"]
    assert out[0].location == "lines 101-101"
    assert out[1].location == "lines 273-292"
    assert out[0].message.startswith("stale Skill ref")


def test_parse_syntax_clean():
    clean = "## Findings\n\n> No findings detected.\n"
    assert parse_syntax(clean) == []


def test_parse_syntax_navigability_projection():
    """ADR 0005: the legacy path projects a passive INFO navigability finding
    (`### N1 (INFO) — navigability: ...`). The composer must parse it into a
    syntax AuditFinding (code N1, severity INFO) with no run.sh/composer change."""
    stdout = (
        "## Findings\n\n"
        "### N1 (INFO) — navigability: 163 ordinal IDs, 0 mode notes, "
        "no SSOT map → consider PR830-style consolidation (collapse phase IDs, "
        "add a mode×phase SSOT table)\n\n"
        "- Proposed refactor: collapse phase IDs, add a mode×phase SSOT table\n"
    )
    out = parse_syntax(stdout)
    assert len(out) == 1
    assert out[0].engine == "syntax"
    assert out[0].code == "N1"
    assert out[0].severity == "INFO"
    assert out[0].message.startswith("navigability: 163 ordinal IDs")


# Real audit.py --no-llm output on flow-dev (stdout YAML; the leading
# NOT_APPLICABLE notices go to stderr, so stdout is pure YAML). Two G8 findings.
SEMANTIC_REAL = """findings:
    - id: g8-001
      axis: G8
      severity: MED
      confidence: high
      title: code block at L273-L292 belongs in references/
      summary: Rule layer flagged a code_block of 20 lines; LLM classified as reference. Suggest moving to REFERENCE.md.
      locations:
        - file: flow-dev/SKILL.md
          lines: L273-L292
      evidence_quote: |
        flow-dev/SKILL.md L273-L292:
          ```bash
      numeric_basis: null
      suggested_action: Extract L273-L292 to REFERENCE.md.
      requires_human: true
    - id: g8-002
      axis: G8
      severity: HIGH
      confidence: high
      title: code block at L432-L480 belongs in references/
      summary: Rule layer flagged a code_block of 49 lines; LLM classified as reference. Suggest moving to REFERENCE.md.
      locations:
        - file: flow-dev/SKILL.md
          lines: L432-L480
      evidence_quote: |
        flow-dev/SKILL.md L432-L480:
          ```bash
      numeric_basis: null
      suggested_action: Extract L432-L480 to REFERENCE.md.
      requires_human: true
"""


def test_parse_semantic_real_stacking_dev():
    out = parse_semantic(SEMANTIC_REAL)
    assert len(out) == 2
    assert all(f.engine == "semantic" for f in out)
    assert [f.code for f in out] == ["G8", "G8"]
    assert [f.severity for f in out] == ["MED", "HIGH"]
    # location comes from the nested locations[0].lines
    assert out[0].location == "L273-L292"
    assert out[0].message == "code block at L273-L292 belongs in references/"


def test_parse_semantic_clean():
    # Clean run: bare `findings:` with no list items (null body).
    assert parse_semantic("findings:\n") == []
