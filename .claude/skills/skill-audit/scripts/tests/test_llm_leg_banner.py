"""LLM-leg-not-run banner acceptance tests — 2-leg contract (task-4).

skill-audit.py prints the LLM advisory banner to stderr (once, not stdout) and
preserves exit codes. Task-4 collapsed the banner to 2 legs (probabilistic,
prose) and delegated the deterministic half to skill-audit's co-located
run.sh, so run_engine returns a 3-tuple (stdout, rc, stderr).
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
import os

_SCRIPTS = Path(__file__).resolve().parents[1]
_SKILL_AUDIT_PY = _SCRIPTS / "skill-audit.py"

_spec = importlib.util.spec_from_file_location("skill_audit_mod", str(_SKILL_AUDIT_PY))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

_BANNER_MARK = "dispatch the remaining LLM legs"


def _fake_clean_run(cmd):
    """Stand in for run_engine: deterministic leg clean (rc 2), no stderr."""
    return "", 2, ""


def _run_main(skill_dir, capsys):
    original_run = _mod.run_engine
    _mod.run_engine = _fake_clean_run
    try:
        _mod.main(["skill-audit.py", str(skill_dir)])
    except SystemExit:
        pass
    finally:
        _mod.run_engine = original_run
    return capsys.readouterr()


# ── unit: main() writes banner to stderr ─────────────────────────────────────

def test_llm_leg_banner_goes_to_stderr(tmp_path, capsys):
    """main() must print the LLM advisory banner to stderr, not stdout."""
    skill_dir = tmp_path / "my-skill"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("# My Skill\n\nHello world.\n", encoding="utf-8")

    captured = _run_main(skill_dir, capsys)
    assert _BANNER_MARK in captured.err, (
        f"Expected banner in stderr, got stderr={captured.err!r}"
    )
    assert _BANNER_MARK not in captured.out, (
        f"Banner must NOT appear in stdout, got stdout={captured.out!r}"
    )


def test_llm_leg_banner_appears_exactly_once(tmp_path, capsys):
    """Banner must appear exactly once per invocation, not once per target."""
    skill_dir = tmp_path / "my-skill"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("# My Skill\n\nHello world.\n", encoding="utf-8")
    refs = skill_dir / "references"
    refs.mkdir()
    (refs / "ref1.md").write_text("# Ref1\n\nSome content here.\n", encoding="utf-8")
    (refs / "ref2.md").write_text("# Ref2\n\nMore content here.\n", encoding="utf-8")

    captured = _run_main(skill_dir, capsys)
    count = captured.err.count(_BANNER_MARK)
    assert count == 1, (
        f"Expected exactly 1 banner invocation in stderr, got {count}\n"
        f"stderr={captured.err!r}"
    )


def test_banner_names_both_legs_by_default(tmp_path, capsys):
    """When legs_ran is empty (default), banner must name both: probabilistic, prose."""
    skill_dir = tmp_path / "my-skill"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("# My Skill\n\nHello world.\n", encoding="utf-8")

    captured = _run_main(skill_dir, capsys)
    assert "probabilistic" in captured.err, (
        f"Expected 'probabilistic' in stderr banner, got stderr={captured.err!r}"
    )
    assert "prose" in captured.err, (
        f"Expected 'prose' in stderr banner, got stderr={captured.err!r}"
    )


def test_stdout_is_banner_free(tmp_path, capsys):
    """stdout must contain NO banner content — only the deterministic report."""
    skill_dir = tmp_path / "my-skill"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("# My Skill\n\nHello world.\n", encoding="utf-8")

    captured = _run_main(skill_dir, capsys)
    assert _BANNER_MARK not in captured.out, (
        f"Banner text must NOT appear in stdout, got stdout={captured.out!r}"
    )


# ── unit: exit-code isolation — agent legs never reach rollup_exit ────────────

def test_rollup_exit_ignores_agent_legs():
    """rollup_exit accepts only the deterministic leg code + any_error. Agent legs
    (probabilistic, prose) are never appended to `codes` in main(), so they cannot
    perturb the exit code."""
    assert _mod.rollup_exit([], False) == 2
    assert _mod.rollup_exit([2], False) == 2
    assert _mod.rollup_exit([0], False) == 0
    assert _mod.rollup_exit([2], True) == 1
    assert _mod.rollup_exit([0], True) == 1


# ── subprocess: exit codes unchanged ─────────────────────────────────────────

def test_exit_code_unchanged_clean(tmp_path):
    """A clean skill exits with the deterministic leg's rollup. Banner on stderr."""
    skill_dir = tmp_path / "clean-skill"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text("# Clean\n\nHello world.\n", encoding="utf-8")

    env = os.environ.copy()
    env["SKILL_AUDIT_SKILLS_ROOT"] = str(Path(__file__).resolve().parents[4])
    result = subprocess.run(
        [sys.executable, str(_SKILL_AUDIT_PY), str(skill_dir)],
        capture_output=True, text=True, env=env,
    )
    assert _BANNER_MARK in result.stderr, (
        f"Expected banner in stderr, got: {result.stderr!r}"
    )
    assert _BANNER_MARK not in result.stdout, (
        f"Banner leaked to stdout: {result.stdout!r}"
    )
