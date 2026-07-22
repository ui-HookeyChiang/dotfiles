"""Tests for bounded in-skill instance-method dispatch (Piece 1).

Verifies that:
  - A method called via obj.method() on an in-skill instantiated class is NOT (c)
  - A genuinely dead method (never accessed) is still (c)
  - Collision guard: stdlib `.read()` does NOT confer liveness on a standalone
    `def read()` when no in-skill class owns `read`
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


# ---------------------------------------------------------------------------
# Fixture: instance-method-skill
# ---------------------------------------------------------------------------

def test_instance_method_bump_not_flagged():
    """Counter.bump() is called via `c.bump()` where `c = Counter()` -- must
    NOT be (c) thanks to instance-method dispatch."""
    fixture = FIXTURES / "instance-method-skill"
    _, out, _ = _run(fixture)
    assert "bump" not in _flagged_c(out), (
        "bump (called via instance dispatch c.bump()) should NOT be flagged (c)")


def test_instance_method_dead_m_still_flagged():
    """Counter.dead_m() is never called anywhere -> must still be (c)."""
    fixture = FIXTURES / "instance-method-skill"
    _, out, _ = _run(fixture)
    assert "dead_m" in _flagged_c(out), (
        "dead_m (genuinely dead method) should be flagged (c)")


# ---------------------------------------------------------------------------
# Fixture: instance-method-collision-skill
# ---------------------------------------------------------------------------

def test_collision_guard_read_still_flagged():
    """Standalone `def read()` with a stdlib `f.read()` call in scope: no
    in-skill class owns `read`, so the stdlib access must NOT confer liveness.
    `read` must remain (c)."""
    fixture = FIXTURES / "instance-method-collision-skill"
    _, out, _ = _run(fixture)
    assert "read" in _flagged_c(out), (
        "read (standalone function, stdlib .read() call) should still be (c)")
