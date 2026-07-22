"""Tests for A1 frontmatter pathology detector (spec 2026-05-29-doc-correctness).

Covers 6 rules + stale-ref subset (R9 #3):
  1. description > 1024 chars (HIGH)
  2. name != dirname (HIGH)
  3. missing description / name (HIGH)
  4. description without "Use when"/"Triggers on" (MED)
  5. argument-hint declared but no <args>/<placeholder> example (LOW)
  6. landing-group missing (LOW)
  7. stale `Skill foo` ref to skill not in plugin oracle (MED)

Also exercises the render_report table-header extension (substring assert per
spec L408 — do NOT use exact match, Task 1.B will extend to 5 cols).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

# Add scripts/ to sys.path so `from audit import ...` works (conftest already
# does this for parents[2] = scripts/).
SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from syntax_audit import (  # noqa: E402
    Finding,
    detect_frontmatter_pathology,
    _build_parsed_context,
    _parse_skill_frontmatter,
    render_report,
)


FIXTURES = Path(__file__).parent / "fixtures" / "frontmatter"
FAKE_PLUGIN_ROOT = FIXTURES / "fake_plugin_root"


@pytest.fixture(autouse=True)
def _isolate_plugin_oracle(monkeypatch):
    """Force stale-ref oracle to use the test fixture's fake plugin root,
    not the developer's real ~/.claude/skills/."""
    monkeypatch.setenv("SKILL_AUDIT_PLUGIN_ROOTS", str(FAKE_PLUGIN_ROOT))


def _run_on(name: str) -> list[Finding]:
    """Run the detector on fixtures/frontmatter/<name>/SKILL.md."""
    skill_md = FIXTURES / name / "SKILL.md"
    content = skill_md.read_text()
    ctx = _build_parsed_context(content)
    return detect_frontmatter_pathology(skill_md, ctx)


# --- Rule 1: description > 1024 ---------------------------------------------

def test_oversized_description_high():
    fs = _run_on("oversized")
    summaries = [f.summary for f in fs]
    assert any("description" in s.lower() and "1024" in s for s in summaries), summaries
    high = [f for f in fs if f.severity == "HIGH" and "description" in f.summary.lower()
            and "1024" in f.summary]
    assert high, fs
    assert high[0].kind == "F"


# --- Rule 2: name != dirname ------------------------------------------------

def test_name_mismatch_high():
    fs = _run_on("name_mismatch_dir")
    high = [f for f in fs if f.severity == "HIGH" and "name" in f.summary.lower()
            and "dirname" in f.summary.lower()]
    assert high, fs
    assert high[0].kind == "F"


# --- Rule 3: missing description / name -------------------------------------

def test_missing_required_high():
    fs = _run_on("missing_required")
    # Missing description -> HIGH
    missing = [f for f in fs if f.severity == "HIGH" and "missing" in f.summary.lower()
               and "description" in f.summary.lower()]
    assert missing, fs


# --- Rule 4: description without trigger phrase -----------------------------

def test_description_no_trigger_med():
    fs = _run_on("description_no_trigger")
    med = [f for f in fs if f.severity == "MED" and "use when" in f.summary.lower()]
    assert med, fs


def test_literal_block_with_use_when_no_finding():
    """description: | multi-line block containing 'Use when' must NOT
    trigger Rule 4 (dogfood baseline regression — spec L51)."""
    fs = _run_on("literal_block_use_when")
    bad = [f for f in fs if f.severity == "MED" and "use when" in f.summary.lower()]
    assert not bad, f"yaml literal block 'Use when' substring check failed: {bad}"


def test_literal_block_without_trigger_emits():
    fs = _run_on("literal_block_no_trigger")
    bad = [f for f in fs if f.severity == "MED" and "use when" in f.summary.lower()]
    assert bad, fs


# --- Rule 5: argument-hint but no <args> example ----------------------------

def test_argument_hint_no_args_low():
    fs = _run_on("argument_hint_no_args")
    low = [f for f in fs if f.severity == "LOW" and "argument-hint" in f.summary.lower()]
    assert low, fs


# --- Rule 6: landing-group missing ------------------------------------------

def test_missing_landing_group_low():
    fs = _run_on("missing_landing_group")
    low = [f for f in fs if f.severity == "LOW" and "landing-group" in f.summary.lower()]
    assert low, fs


# --- Rule 7: stale Skill ref ------------------------------------------------

def test_stale_skill_ref_med():
    fs = _run_on("stale_skill_ref")
    stale = [f for f in fs if f.severity == "MED" and "stale" in f.summary.lower()
             and "nonexistent-skill" in f.summary]
    assert stale, fs


def test_stale_skill_ref_excludes_placeholders():
    """Placeholders like 'Skill foo', 'Skill <name>', 'Skill XXX' must NOT
    trigger stale-ref findings (spec Design L256)."""
    fs = _run_on("stale_skill_ref")
    placeholders = [f for f in fs
                    if "stale" in f.summary.lower()
                    and any(p in f.summary for p in (" foo", "<name>", " XXX"))]
    assert not placeholders, f"placeholder Skill refs leaked: {placeholders}"


def test_stale_skill_ref_excludes_in_code_fence():
    """Stale-ref must not trigger for `Skill xxx` inside fenced code blocks."""
    fs = _run_on("stale_skill_ref")
    incode = [f for f in fs if "stale" in f.summary.lower()
              and "in-fence-skill" in f.summary]
    assert not incode, f"code-fence Skill ref leaked: {incode}"


# --- Clean fixture: zero findings -------------------------------------------

def test_ok_fixture_no_findings():
    fs = _run_on("ok")
    assert fs == [], fs


# --- _parse_skill_frontmatter contract --------------------------------------

def test_parse_frontmatter_plain_scalar():
    fm = _parse_skill_frontmatter(
        "---\nname: foo\ndescription: bar\nargument-hint: <x>\n---\n# body\n"
    )
    assert fm["name"] == "foo"
    assert fm["description"] == "bar"
    assert fm["argument-hint"] == "<x>"


def test_parse_frontmatter_literal_block():
    fm = _parse_skill_frontmatter(
        '---\nname: foo\ndescription: |\n  line one\n  line two with Use when bar.\n'
        'argument-hint: <x>\n---\n# body\n'
    )
    assert fm["name"] == "foo"
    # literal block joined with newlines (yaml `|` preserves newlines)
    assert "line one" in fm["description"]
    assert "Use when" in fm["description"]
    assert fm["argument-hint"] == "<x>"


def test_parse_frontmatter_quoted_string():
    fm = _parse_skill_frontmatter(
        '---\nname: foo\ndescription: "Use when something."\n---\n'
    )
    assert fm["description"] == "Use when something."


def test_parse_frontmatter_missing_returns_empty():
    fm = _parse_skill_frontmatter("# no frontmatter\n")
    assert fm == {}


# --- render_report table-header substring -----------------------------------

def test_render_report_includes_frontmatter_column():
    """Per spec L408, table-header assertion must use substring not exact
    match (Task 1.B will extend to 5 cols)."""
    target = FIXTURES / "ok" / "SKILL.md"
    md = render_report(
        target=target, skill_name="ok", total_lines=10,
        scripts_dir=None, findings=[], spec_path=None,
        spec_inline=None, host_root=None,
    )
    assert "Frontmatter" in md
    assert "## Bloat metrics" in md  # H2 unchanged per test_h2_anchors lockup


def test_render_report_counts_F_findings():
    f = Finding(
        kind="F", severity="HIGH", locations=[(2, 2)],
        summary="description exceeds 1024 char limit (1187 chars)",
        refactor="trim description", saved_lines=0,
    )
    md = render_report(
        target=Path("/tmp/test/SKILL.md"), skill_name="test", total_lines=10,
        scripts_dir=None, findings=[f], spec_path=None,
        spec_inline=None, host_root=None,
    )
    # Per-severity row should reflect F count under "Frontmatter" column.
    assert "F1 (HIGH)" in md
    # The HIGH row should show 1 in the Frontmatter column.
    high_row = next(ln for ln in md.splitlines() if ln.startswith("| HIGH"))
    assert "| 1 |" in high_row  # at least one count of 1 (frontmatter)
