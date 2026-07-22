"""Tests for the navigability -> passive INFO finding projection (ADR 0005).

The legacy path (`syntax_audit.py _run_legacy`) computes compute_navigability
on the SKILL.md target and, when score >= NAV_PROJECT_THRESHOLD (85), injects
ONE passive INFO finding so render_report emits:
    ### N1 (INFO) — navigability: <ids> ordinal IDs, <modes> mode notes, ...

Passive: an INFO-only run must NOT flip the exit code (kind "N" is in the
passive set alongside "I"/"V").
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from audit import (  # noqa: E402
    NAV_PROJECT_THRESHOLD,
    project_metric_finding,
    Finding,
)

NAV_FIXTURES = Path(__file__).parent / "fixtures" / "navigability"


def _run_legacy_subprocess(skill_md: Path) -> subprocess.CompletedProcess:
    """Run the legacy detector via syntax_audit.sh --no-spec, capturing
    stdout + exit code (the real composer entry path)."""
    sh = SCRIPTS_DIR / "syntax_audit.sh"
    return subprocess.run(
        ["bash", str(sh), str(skill_md), "--no-spec"],
        capture_output=True, text=True,
    )


# ---------------------------------------------------------------------------
# Generic bridge helper

def test_bridge_projects_at_threshold():
    """score == threshold (85) -> a Finding is produced."""
    f = project_metric_finding(
        score=85.0, threshold=NAV_PROJECT_THRESHOLD,
        kind="N", severity="INFO", summary="navigability: x", refactor="do y",
    )
    assert isinstance(f, Finding)
    assert f.kind == "N"
    assert f.severity == "INFO"


def test_bridge_below_threshold_is_none():
    """score 84 (< 85) -> None, no finding."""
    f = project_metric_finding(
        score=84.0, threshold=NAV_PROJECT_THRESHOLD,
        kind="N", severity="INFO", summary="navigability: x", refactor="do y",
    )
    assert f is None


# ---------------------------------------------------------------------------
# Legacy path projection — high-nav input (flow-dev fixture, nav=100)
#
# Projection is gated on `target.name == "SKILL.md"` (a SKILL.md-level metric),
# so the test copies the `*-SKILL.md` fixture into a literal `SKILL.md` file —
# mirroring how run.sh always invokes the leg on `<dir>/SKILL.md`.

def _as_skill_md(fixture: Path, tmp_path: Path) -> Path:
    dst = tmp_path / "SKILL.md"
    shutil.copy(fixture, dst)
    return dst


def test_legacy_high_nav_emits_n1_info(tmp_path):
    target = _as_skill_md(NAV_FIXTURES / "stack-dev-SKILL.md", tmp_path)
    proc = _run_legacy_subprocess(target)
    assert "### N1 (INFO) — navigability:" in proc.stdout, proc.stdout
    assert "ordinal IDs" in proc.stdout
    assert "no SSOT map" in proc.stdout


def test_legacy_n1_info_does_not_flip_exit(tmp_path):
    """The N1 INFO projection is passive: a SKILL.md whose ONLY finding is the
    projection keeps the legacy exit at 2 ('no NON-passive findings'). Build a
    clean-but-high-nav SKILL.md so N1 is the sole finding — if the projection
    were active it would push the exit to 0."""
    # frontmatter name must match parent dirname (avoid the F1 HIGH finding);
    # dense Phase/Step landmarks drive navigability >= 85 with no other smell.
    skill_dir = tmp_path / "nav-only"
    skill_dir.mkdir()
    body = [
        "---", "name: nav-only",
        "description: dense ordinal landmarks. Use when navigating phases.",
        "landing-group: workflow", "---",
        "", "# Nav only", "",
    ]
    for n in range(14):
        body.append(f"## Phase {n} — do stuff")
        body.append(f"Step {n}.1: first thing. Step {n}.2: second thing.")
        body.append(f"See Amendment A{n} for the exception. Gate {n}: check it.")
        body.append("")
    skill_md = skill_dir / "SKILL.md"
    skill_md.write_text("\n".join(body))
    # Rule 8a requires agents/openai.yaml; create a valid one so 8a does not fire.
    agents_dir = skill_dir / "agents"
    agents_dir.mkdir()
    (agents_dir / "openai.yaml").write_text(
        'interface:\n  display_name: "Nav Only"\n'
        '  short_description: "Test fixture for navigability projection."\n'
    )

    proc = _run_legacy_subprocess(skill_md)
    assert "### N1 (INFO) — navigability:" in proc.stdout, proc.stdout
    # Confirm N1 really is the only finding (no R/S/F/L/V/HIGH/MED lines).
    other = [l for l in proc.stdout.splitlines()
             if l.startswith("### ") and "N1 (INFO)" not in l]
    assert other == [], f"expected only N1, also got: {other}"
    assert proc.returncode == 2, (
        f"N1 INFO flipped exit code: got {proc.returncode}\n{proc.stdout}"
    )


# ---------------------------------------------------------------------------
# Legacy path — low-nav input (skill-writer fixture, nav=73 < 85) -> no N1

def test_legacy_low_nav_no_projection(tmp_path):
    target = _as_skill_md(NAV_FIXTURES / "skill-writer-SKILL.md", tmp_path)
    proc = _run_legacy_subprocess(target)
    assert "### N1 (INFO)" not in proc.stdout, proc.stdout
    assert "navigability:" not in proc.stdout, proc.stdout


def test_legacy_reference_file_no_projection(tmp_path):
    """Navigability is a SKILL.md-level metric — a high-nav references/*.md
    target (name != SKILL.md) must NOT project, even above threshold."""
    ref = tmp_path / "loop-protocol.md"  # a reference file, not SKILL.md
    body = ["# Loop protocol", ""]
    for n in range(14):
        body.append(f"## Phase {n} — do stuff")
        body.append(f"Step {n}.1: first. Step {n}.2: second. Gate {n}: check.")
        body.append(f"See Amendment A{n} for the exception.")
        body.append("")
    ref.write_text("\n".join(body))
    proc = _run_legacy_subprocess(ref)
    assert "### N1 (INFO)" not in proc.stdout, proc.stdout
    assert "navigability:" not in proc.stdout, proc.stdout
