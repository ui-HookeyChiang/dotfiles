"""Regression tests for the python-edge + example-literal fix (design 2026-06-20).

Three FP classes the audit family triggered on reachability.py:
  1. FP-1/FP-2 — no python import/call edges (intra-package modules look rootless)
  2. a/b boundary — a module imported only by a tests/ file must be (b), not (c)
  3. FP-3 — example-only invoke literal in a reference fence flagged (f)

Plus no-new-false-negative guards: a genuinely unimported module still flags (c),
and a real dangling invoke with no example marker still fires (f).
"""
import subprocess
import sys
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1] / "reachability.py"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "py-edge-skill"
REPO = Path(__file__).resolve().parents[3]


def _run(skill_dir):
    r = subprocess.run([sys.executable, str(ENGINE), str(skill_dir)],
                       capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def _flagged(out, cls):
    """Names flagged with the given (cls) marker in the report table."""
    names = set()
    marker = f"({cls})"
    for line in out.splitlines():
        if marker in line and "|" in line:
            cells = [c.strip().strip("`") for c in line.split("|")]
            # cells: ['', class, sev, kind, name, where, note, '']
            if len(cells) >= 6 and cells[1].startswith(marker):
                names.add(cells[4])
    return names


def _flagged_c(out):
    return _flagged(out, "c")


def _flagged_f(out):
    return _flagged(out, "f")


def _flagged_b(out):
    return _flagged(out, "b")


# ---------------------------------------------------------------------------
# Case 1: python import/call edge — imported module is live, unimported is dead
# ---------------------------------------------------------------------------

def test_imported_module_is_live():
    """foo.py is `from detectors import foo` + foo.detect() from a root-reachable
    audit.py -> live, NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "foo.py" not in _flagged_c(out)


def test_unimported_module_stays_c():
    """bar.py is imported by nobody -> still (c) (no over-suppression)."""
    _, out, _ = _run(FIXTURE)
    assert "bar.py" in _flagged_c(out)


# ---------------------------------------------------------------------------
# Case 2: a/b boundary — test-only import classified (b), not (a)/(c)
# ---------------------------------------------------------------------------

def test_test_only_import_is_b():
    """test_helper.py is imported ONLY by scripts/tests/test_x.py -> (b),
    NOT (a) (would not appear) and NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "test_helper.py" in _flagged_b(out)
    assert "test_helper.py" not in _flagged_c(out)


# ---------------------------------------------------------------------------
# Case 3: example-literal suppression in reference fences
# ---------------------------------------------------------------------------

def test_proposed_refactor_example_not_dangling():
    """hypothetical.sh under a 'Proposed refactor:' marker -> suppressed, NOT (f)."""
    _, out, _ = _run(FIXTURE)
    assert "hypothetical.sh" not in _flagged_f(out)


def test_unmarked_dangling_still_fires():
    """missing-real.sh with NO marker -> real dangling target, IS (f)."""
    _, out, _ = _run(FIXTURE)
    assert "missing-real.sh" in _flagged_f(out)


def test_incidental_keyword_does_not_suppress():
    """also-missing.sh's introducing line carries no marker; 'example' only
    appears in an unrelated prior paragraph -> STILL fires (f)."""
    _, out, _ = _run(FIXTURE)
    assert "also-missing.sh" in _flagged_f(out)


def test_weak_would_in_intro_still_fires():
    """stale-cleanup.sh sits in a fence whose INTRODUCING prose line contains the
    bare WEAK marker 'would' ("Running this would clean up:"). A weak marker in
    the intro must NOT suppress a real dangling invoke -> STILL fires (f).
    (false-alive << false-dead: a bare common word in real prose must not hide a
    genuinely missing target.)"""
    _, out, _ = _run(FIXTURE)
    assert "stale-cleanup.sh" in _flagged_f(out)


def test_weak_proposed_in_intro_still_fires():
    """skill-cleanup.sh's INTRODUCING prose line contains the bare WEAK marker
    'proposed' ("The proposed cleanup is run ..."). A bare 'proposed' in the
    intro (vs the STRONG phrase 'proposed refactor') must NOT suppress a real
    dangling invoke -> STILL fires (f)."""
    _, out, _ = _run(FIXTURE)
    assert "skill-cleanup.sh" in _flagged_f(out)


# ---------------------------------------------------------------------------
# Case 4: regression on the real audit-family skills
# ---------------------------------------------------------------------------

def _skip_if_absent(name):
    import pytest
    d = REPO / name
    if not (d / "SKILL.md").is_file():
        pytest.skip(f"{name} not present")
    return d


def test_semantic_audit_modules_not_c():
    d = _skip_if_absent("skill-audit")
    _, out, _ = _run(d)
    c = _flagged_c(out)
    # __init__.py is the load-bearing assertion here: without the relative-import
    # edge (`from . import g1_cross_skill_dup, g8_progressive_disclosure`) it would
    # be flagged (c). The two g*.py basenames are belt-and-suspenders — they have
    # a direct dynamic-import consumer so they never reach (c) even on main.
    for m in ("g1_cross_skill_dup.py", "g8_progressive_disclosure.py", "__init__.py"):
        assert m not in c, f"{m} falsely flagged (c)"


def test_syntax_audit_modules_not_c_and_no_promote_f():
    d = _skip_if_absent("skill-audit")
    _, out, _ = _run(d)
    c = _flagged_c(out)
    for m in ("yaml_lite.py", "metrics.py", "ranker.py", "report.py", "__init__.py"):
        assert m not in c, f"{m} falsely flagged (c)"
    assert not any("promote-with-verify" in n for n in _flagged_f(out)), \
        "promote-with-verify example literal falsely flagged (f)"


def test_audit_finding_not_c():
    d = _skip_if_absent("skill-audit")
    _, out, _ = _run(d)
    assert "audit_finding.py" not in _flagged_c(out)


# ---------------------------------------------------------------------------
# Case 5: self-dogfood stays clean
# ---------------------------------------------------------------------------

def test_self_dogfood_still_exits_2():
    """reachability.py on skill-audit still exits 2 (the python-edge
    logic must not make the engine flag its own code)."""
    rc, out, _ = _run(REPO / "skill-audit")
    assert rc == 2, f"self-dogfood not clean (exit {rc}):\n{out}"
