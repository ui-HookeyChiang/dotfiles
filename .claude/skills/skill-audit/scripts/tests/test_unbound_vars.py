"""Tests for Detector 6 — unbound bash variables (kind="V").

Covers the FP-floor trust contract:
  - clean skill (no unbound) -> V findings == []
  - skill-writer-shaped positive: 5 unbound vars {SPEC_HASH,RUN,VERDICT,DEPTH,TARGET}
  - source-bound: fence `source scripts/helper.sh` where helper.sh sets FOO= -> silent
  - subprocess: `bash scripts/helper.sh` (NOT source) then `echo $FOO` -> FOO IS a finding
  - known-env: $HOME (POSIX) and $SD_FLAG (matches SD_*) -> silent
  - guard: ${MAYBE:-x} and `: "${MAYBE:?...}"` -> silent (no self-flag)
  - tricky quoting -> []: $VAR in a # comment, in single-quotes, in <<'QUOTED' heredoc
"""
from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from audit import (  # noqa: E402
    detect_unbound_vars,
    parse_code_blocks,
    Finding,
)

FIXTURES = Path(__file__).parent / "fixtures" / "unbound"


def _run_on(name: str) -> list[Finding]:
    """Run detect_unbound_vars on fixtures/unbound/<name>/SKILL.md.

    known-env.txt is always loaded from audit.py's own scripts/ dir (the
    auditor's data file), so we don't need to pass it from the test.
    scripts_dir is passed as the fixture's scripts/ subdir (for source resolution).
    """
    skill_md = FIXTURES / name / "SKILL.md"
    content = skill_md.read_text()
    lines = content.splitlines()
    blocks = parse_code_blocks(lines)
    skill_dir = skill_md.parent
    scripts_dir = skill_dir / "scripts"
    return detect_unbound_vars(blocks, skill_dir, scripts_dir)


# ---------------------------------------------------------------------------
# Clean baseline: zero V findings

def test_clean_no_findings():
    fs = _run_on("clean")
    v = [f for f in fs if f.kind == "V"]
    assert v == [], f"expected no V findings on clean fixture, got: {v}"


# ---------------------------------------------------------------------------
# Positive: 5 unbound vars (skill-writer-shaped)

def test_positive_five_vars():
    fs = _run_on("positive")
    v = [f for f in fs if f.kind == "V"]
    names = {f.summary.split("$", 1)[1].split(" ")[0] for f in v}
    expected = {"SPEC_HASH", "RUN", "VERDICT", "DEPTH", "TARGET"}
    assert names == expected, (
        f"expected unbound vars {expected}, got {names!r}\n"
        f"findings: {[(f.summary) for f in v]}"
    )
    assert len(v) == 5, f"expected exactly 5 V findings, got {len(v)}: {[f.summary for f in v]}"


# ---------------------------------------------------------------------------
# Source-bound: sourced script sets FOO -> silent

def test_source_bound_silent():
    """fence `source scripts/helper.sh` where helper.sh sets FOO= -> no V finding for FOO."""
    fs = _run_on("source_bound")
    v = [f for f in fs if f.kind == "V"]
    foo_findings = [f for f in v if "FOO" in f.summary]
    assert not foo_findings, (
        f"FOO should be silenced (source-bound), but got finding: {foo_findings}"
    )


# ---------------------------------------------------------------------------
# Subprocess: `bash scripts/helper.sh` does NOT silence FOO

def test_subprocess_not_silenced():
    """bash scripts/helper.sh (subprocess) then echo $FOO -> FOO IS a finding."""
    fs = _run_on("subprocess")
    v = [f for f in fs if f.kind == "V"]
    foo_findings = [f for f in v if "FOO" in f.summary]
    assert foo_findings, (
        "FOO should be unbound (subprocess, not source), but no V finding emitted"
    )


# ---------------------------------------------------------------------------
# Known-env: $HOME (POSIX) and $SD_FLAG (SD_* glob) -> silent

def test_known_env_silent():
    """$HOME (POSIX) and $SD_FLAG (matches SD_* prefix) must not produce findings."""
    fs = _run_on("known_env")
    v = [f for f in fs if f.kind == "V"]
    home_findings = [f for f in v if "HOME" in f.summary]
    sd_findings = [f for f in v if "SD_FLAG" in f.summary]
    assert not home_findings, f"$HOME should be silenced (POSIX env), got: {home_findings}"
    assert not sd_findings, f"$SD_FLAG should be silenced (SD_* glob), got: {sd_findings}"


# ---------------------------------------------------------------------------
# Guard: ${MAYBE:-x} and `: "${MAYBE:?set by harness}"` -> silent

def test_operator_guard_silent():
    """${MAYBE:-x} and ${MAYBE:?...} operator expansions must NOT be flagged."""
    fs = _run_on("guard")
    v = [f for f in fs if f.kind == "V"]
    maybe_findings = [f for f in v if "MAYBE" in f.summary]
    assert not maybe_findings, (
        f"${'{MAYBE:-x}'} / ${'{MAYBE:?...}'} guard must not self-flag, got: {maybe_findings}"
    )


# ---------------------------------------------------------------------------
# Tricky quoting: $VAR in comment / single-quotes / <<'QUOTED' heredoc -> []

def test_tricky_quoting_no_findings():
    """$VAR in # comment, in 'single quotes', or in <<'QUOTED' heredoc -> no V findings."""
    fs = _run_on("tricky_quoting")
    v = [f for f in fs if f.kind == "V"]
    assert v == [], (
        f"expected no V findings (all vars in comments/single-quotes/literal heredoc), "
        f"got: {[f.summary for f in v]}"
    )


# ---------------------------------------------------------------------------
# Kind and severity checks

def test_v_findings_have_correct_kind_and_severity():
    """All V findings must have kind='V' and severity='INFO'."""
    fs = _run_on("positive")
    v = [f for f in fs if f.kind == "V"]
    assert v, "positive fixture must emit V findings"
    for f in v:
        assert f.kind == "V", f"unexpected kind {f.kind!r} on {f.summary}"
        assert f.severity == "INFO", f"unexpected severity {f.severity!r} on {f.summary}"


# ---------------------------------------------------------------------------
# Render-report table includes Unbound vars column

# ---------------------------------------------------------------------------
# Passive exit code: a V-only skill (no R/S/F/L) must NOT flip legacy exit 2->0.
# This is the load-bearing Q2 invariant — kind="V" is INFO/passive like "I",
# so the exit code stays a pure bloat signal (no surprise regression for CI /
# dogfood callers branching on exit 2 = clean).

def test_passive_exit_code_v_only(capsys):
    from audit import main
    rc = main([str(FIXTURES / "positive" / "SKILL.md"), "--no-spec"])
    capsys.readouterr()  # swallow the report
    assert rc == 2, (
        "a V-only skill (5 unbound vars, zero R/S/F/L) must exit 2 — Detector 6 "
        f"is passive and must not flip the legacy exit code, got {rc}"
    )


def test_render_report_includes_unbound_column():
    """render_report table header must contain 'Unbound vars' column."""
    from audit import render_report
    md = render_report(
        target=FIXTURES / "clean" / "SKILL.md",
        skill_name="clean",
        total_lines=10,
        scripts_dir=None,
        findings=[],
        spec_path=None,
        spec_inline=None,
        host_root=None,
    )
    assert "Unbound vars" in md, f"'Unbound vars' column missing from report header:\n{md[:400]}"
