"""Regression tests for the @property false-positive fix (design 2026-06-23).

reachability.py flagged @property accessors as (c) zero-reader because:
  1. enumerate_functions never captured the @property decorator.
  2. function_qualified_called only counts self/alias qualifiers, missing
     local-var access (para.is_candidate, obj.flag).

These tests pin the fix: a @property accessed via a local var must NOT be (c),
while genuinely dead plain functions still must be.
"""
import subprocess
import sys
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1] / "reachability.py"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "property-skill"
REPO = Path(__file__).resolve().parents[3]


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
# Case 1: @property accessed via local var must NOT be (c)
# ---------------------------------------------------------------------------

def test_property_accessed_via_local_var_not_flagged():
    """@property `flag` on Item is accessed as `obj.flag` through a local var
    in process() which IS reached from main.py (live surface). Pre-fix: falsely
    flagged (c). Post-fix: NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "flag" not in _flagged_c(out), (
        "flag (@property accessed via local var obj.flag) was falsely flagged (c). "
        "The @property fix is not applied.")


# ---------------------------------------------------------------------------
# Case 2: genuinely dead plain function must still be (c) (negative control)
# ---------------------------------------------------------------------------

def test_really_dead_plain_function_still_flagged():
    """really_dead() has no caller anywhere -> must still be (c).
    The fix must not blanket-suppress all dead functions."""
    _, out, _ = _run(FIXTURE)
    assert "really_dead" in _flagged_c(out), (
        "really_dead() was NOT flagged (c) — the fix over-suppressed.")


def test_property_mentioned_only_in_prose_still_flagged():
    """prose_only_prop is a @property referenced ONLY as `item.prose_only_prop`
    in SKILL.md prose — never accessed in any .py source. A prose `obj.name`
    mention is not a real edge, so it must still be (c). Guards review-H3: the
    accept-path scans the live PYTHON corpus only, not SKILL.md/reference prose."""
    _, out, _ = _run(FIXTURE)
    assert "prose_only_prop" in _flagged_c(out), (
        "prose_only_prop was cleared by a prose-only `item.prose_only_prop` "
        "mention — property_accessed leaked into SKILL.md/reference text (H3).")


def test_dead_property_still_flagged():
    """dead_prop is a @property NEVER accessed anywhere -> must still be (c).
    Guards against a regression that suppresses all @property unconditionally,
    ignoring property_accessed(). The accept-path is gated on BOTH is_property
    AND an actual attribute-access edge."""
    _, out, _ = _run(FIXTURE)
    assert "dead_prop" in _flagged_c(out), (
        "dead_prop (@property with zero access) was NOT flagged (c) — the fix "
        "suppresses @property unconditionally instead of requiring a real access edge.")


# ---------------------------------------------------------------------------
# Case 3: same-named non-property method with unknown-local access stays (c)
# ---------------------------------------------------------------------------

def test_non_property_with_unknown_local_access_still_flagged():
    """shared() is a plain (non-@property) dead function. Its name appears as
    x.shared in mod.py where x is an unknown local. The qualifier relaxation is
    @property-only — shared() must still be (c)."""
    _, out, _ = _run(FIXTURE)
    assert "shared" in _flagged_c(out), (
        "shared() (plain non-property) was NOT flagged (c) — the fix leaked the "
        "property-only relaxation to plain methods.")


# ---------------------------------------------------------------------------
# Case 4: regression on the real skill-audit (formerly skill-audit)
# ---------------------------------------------------------------------------

def _skip_if_absent(name):
    import pytest
    d = REPO / name
    if not (d / "SKILL.md").is_file():
        pytest.skip(f"{name} not present")
    return d


def test_probabilistic_audit_properties_not_c():
    """line_count, is_candidate, lines_field on Paragraph in g1_cross_skill_dup.py
    are all @property accessors accessed via local vars (para.is_candidate,
    p.line_count, para_a.lines_field) — must NOT be (c) after the fix."""
    d = _skip_if_absent("skill-audit")
    _, out, _ = _run(d)
    c = _flagged_c(out)
    for fn in ("is_candidate", "line_count", "lines_field"):
        assert fn not in c, (
            f"{fn} (@property in g1_cross_skill_dup.py) still falsely (c) — "
            "fix not applied to real skill.")
