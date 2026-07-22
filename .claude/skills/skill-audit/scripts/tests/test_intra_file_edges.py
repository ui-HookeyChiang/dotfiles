"""Regression tests for intra-file (same-file) call edges (issue 2026-06-22).

reachability.py flagged a function (c) zero-reader when its only callers live in
the SAME file, IF that file is non-live (excluded from live_text). Repro:
skill-audit's `_section`/`_strip_ticks` in audit_finding.py (a test-only module)
were flagged HIGH zero-reader despite live intra-file callers. The fix searches
each function's OWN defining file for a caller, regardless of file liveness.

The over-suppression guard: a function with NO caller anywhere (`orphan`) must
STILL flag (c).
"""
import subprocess
import sys
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1] / "reachability.py"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "intra-file-skill"
REPO = Path(__file__).resolve().parents[3]


def _run(skill_dir):
    r = subprocess.run([sys.executable, str(ENGINE), str(skill_dir)],
                       capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def _flagged_c(out):
    names = set()
    for line in out.splitlines():
        if "(c)" in line and "|" in line:
            cells = [c.strip().strip("`") for c in line.split("|")]
            if len(cells) >= 6 and cells[1].startswith("(c)"):
                names.add(cells[4])
    return names


def test_intra_file_caller_is_not_zero_reader():
    """`_section` defined + called only within helper.py (non-live module) ->
    NOT (c) (the intra-file caller `parse` is a live edge)."""
    _, out, _ = _run(FIXTURE)
    assert "_section" not in _flagged_c(out)


def test_orphan_with_no_caller_stays_zero_reader():
    """`orphan` has no caller anywhere -> STILL (c) (no over-suppression)."""
    _, out, _ = _run(FIXTURE)
    assert "orphan" in _flagged_c(out)


def test_skill_audit_intra_file_helpers_not_zero_reader():
    """The real reported case: skill-audit's `_section` + `_strip_ticks` in
    audit_finding.py have live intra-file callers -> NOT (c)."""
    import pytest
    d = REPO / "skill-audit"
    if not (d / "SKILL.md").is_file():
        pytest.skip("skill-audit not present")
    _, out, _ = _run(d)
    c = _flagged_c(out)
    assert "_section" not in c, "_section has intra-file callers (L68, L108)"
    assert "_strip_ticks" not in c, "_strip_ticks has an intra-file caller (L79)"
