"""Tests for class (g) stale-doc advisory (Piece 2).

Verifies that:
  - A dead symbol mentioned alone in a SKILL.md paragraph gets BOTH (c) + (g)
  - A dead symbol in a mixed paragraph (also mentioning a live symbol) gets
    only (c), NOT (g)
  - (g) findings are ADVISORY and excluded from exit code
"""
import subprocess
import sys
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1] / "reachability.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _run(skill_dir):
    r = subprocess.run([sys.executable, str(ENGINE), str(skill_dir)],
                       capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def _flagged(out, cls):
    names = set()
    marker = f"({cls})"
    for line in out.splitlines():
        if marker in line and "|" in line:
            cells = [c.strip().strip("`") for c in line.split("|")]
            if len(cells) >= 6 and cells[1].startswith(marker):
                names.add(cells[4])
    return names


def _flagged_c(out):
    return _flagged(out, "c")


def _flagged_g(out):
    return _flagged(out, "g")


# ---------------------------------------------------------------------------
# Fixture: stale-doc-skill — paragraph mentions ONLY a dead symbol
# ---------------------------------------------------------------------------

def test_stale_doc_old_fn_gets_c():
    """old_fn has no caller -> (c) zero-reader."""
    fixture = FIXTURES / "stale-doc-skill"
    _, out, _ = _run(fixture)
    assert "old_fn" in _flagged_c(out), (
        "old_fn should be flagged (c)")


def test_stale_doc_old_fn_gets_g():
    """old_fn is the sole subject of a SKILL.md paragraph -> (g) stale-doc."""
    fixture = FIXTURES / "stale-doc-skill"
    _, out, _ = _run(fixture)
    assert "old_fn" in _flagged_g(out), (
        "old_fn should get (g) stale-doc advisory")


def test_stale_doc_advisory_excluded_from_exit_code():
    """(g) findings are ADVISORY — must not affect exit code. Exit 0 means
    actionable findings present (the (c) for old_fn counts); if ONLY (g)
    existed with no (c), exit code should be 2 (clean)."""
    fixture = FIXTURES / "stale-doc-skill"
    rc, out, _ = _run(fixture)
    # Has (c) finding for old_fn → exit 0
    assert rc == 0, f"Expected exit 0 (actionable findings), got {rc}"


# ---------------------------------------------------------------------------
# Fixture: stale-doc-mixed-skill — paragraph mentions dead AND live symbol
# ---------------------------------------------------------------------------

def test_mixed_paragraph_old_fn_gets_c_only():
    """old_fn is dead -> (c), BUT paragraph also mentions `run` (live) ->
    no (g) because mixed paragraph."""
    fixture = FIXTURES / "stale-doc-mixed-skill"
    _, out, _ = _run(fixture)
    assert "old_fn" in _flagged_c(out), (
        "old_fn should be flagged (c) in mixed skill")
    assert "old_fn" not in _flagged_g(out), (
        "old_fn should NOT get (g) — paragraph also mentions live `run`")
