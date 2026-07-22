"""Regression tests for the false-positive refine (design 2026-06-16).

Three FP classes the red-team found on flow-dev:
  1. cross-script JSON field pairing  (Tier 1)
  2. prose-root weak edge             (Tier 2)
  3. intra-script function liveness + process-sub/awk callers (Tier 2)

Plus the no-new-false-negative guard: a write-only field and a truly
unreferenced script MUST still flag (c).
"""
import subprocess
import sys
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1] / "reachability.py"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "fp-refine-skill"
BASH_SOURCE_FIXTURE = (
    Path(__file__).resolve().parent / "fixtures" / "bash-source-prefix-skill")
REPO = Path(__file__).resolve().parents[3]


def _run(skill_dir):
    r = subprocess.run([sys.executable, str(ENGINE), str(skill_dir)],
                       capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def _flagged_c(out):
    """Names flagged (c) in the report table."""
    names = set()
    for line in out.splitlines():
        if "(c)" in line and "|" in line:
            cells = [c.strip().strip("`") for c in line.split("|")]
            # cells: ['', class, sev, kind, name, where, note, '']
            if len(cells) >= 6:
                names.add(cells[4])
    return names


# ---------------------------------------------------------------------------
# Fixture: the discrimination contract
# ---------------------------------------------------------------------------

def test_fixture_paired_field_is_live():
    """A field written by producer.sh and read (.paired_field) by consumer.sh
    is a cross-script contract -> NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "paired_field" not in _flagged_c(out)


def test_fixture_cmdsub_dirname_invoked_script_is_live():
    """consumer.sh is invoked only via `bash "$(dirname "$0")/consumer.sh"`
    (command-substitution dir prefix) -> NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "consumer.sh" not in _flagged_c(out)


def test_fixture_bash_source_prefix_lib_is_live():
    """helper.sh is sourced via `source "${BASH_SOURCE[0]%/*}/lib/helper.sh"`
    (BASH_SOURCE parameter-expansion dir prefix) -> NOT (c)."""
    _, out, _ = _run(BASH_SOURCE_FIXTURE)
    assert "helper.sh" not in _flagged_c(out)


def test_fixture_writeonly_field_stays_c():
    """A field written but read by nobody MUST still flag (c) — the refine
    must not blanket-suppress."""
    _, out, _ = _run(FIXTURE)
    assert "writeonly_field" in _flagged_c(out)


def test_fixture_prose_root_script_is_live():
    """helper-prose.sh is invoked only via SKILL.md backtick prose -> weak-live
    root, NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "helper-prose.sh" not in _flagged_c(out)


def test_fixture_orphan_script_stays_c():
    """orphan.sh is referenced nowhere -> still (c) (no-false-negative guard)."""
    _, out, _ = _run(FIXTURE)
    assert "orphan.sh" in _flagged_c(out)


def test_fixture_processsub_function_is_live():
    """emit_lines is called via process-substitution <(emit_lines) inside its
    own (prose-root-live) script -> NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "emit_lines" not in _flagged_c(out)


def test_fixture_awk_internal_function_is_live():
    """awk_strip is defined+called inside an awk program body -> NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "awk_strip" not in _flagged_c(out)


# ---------------------------------------------------------------------------
# Regression corpus: flow-dev batch-2 FPs must drop out
# ---------------------------------------------------------------------------

STACKING_FPS = {
    "write-lock.sh", "phase-5-cleanup.sh", "pre-merge-sanity-common.sh",
    "skill_version", "current_branch_at_phase_0", "lock_action", "lock_path",
    "find_call_sites", "normalize_for_match", "parse_helpers",
    "resolve_canonical_prefix", "strip_quotes",
}


def test_stacking_dev_fps_no_longer_c():
    """All 11 batch-2 false positives must no longer be flagged (c)."""
    sd = REPO / "flow-dev"
    if not (sd / "SKILL.md").is_file():
        import pytest
        pytest.skip("flow-dev not present")
    _, out, _ = _run(sd)
    still = STACKING_FPS & _flagged_c(out)
    assert not still, f"still flagged (c): {sorted(still)}"


def test_self_dogfood_stays_clean():
    """skill-audit on itself stays clean (exit 2)."""
    skill = REPO / "skill-audit"
    rc, out, _ = _run(skill)
    assert rc == 2, f"self-dogfood not clean (exit {rc}):\n{out}"
