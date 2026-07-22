"""C5 — assert_audit_complete gate tests.

Tests the bash function assert_audit_complete in _shared/lib/sh/sandwich-trace.sh:
  - 1-of-2 audit-leg traces for a skill -> incomplete (non-zero + lists missing)
  - 2-of-2 audit-leg traces for a skill -> complete (exit 0)

The audit dispatches 2 legs by determinism: {probabilistic, prose}.
Uses write_audit_leg_trace to write the traces, then asserts via assert_audit_complete.
"""
from __future__ import annotations

import subprocess
import tempfile
import os
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[3]
_TRACE_SH = _REPO_ROOT / "_shared/lib/sh/sandwich-trace.sh"


def _run_bash(script: str, env: dict | None = None) -> subprocess.CompletedProcess:
    """Run a bash snippet that sources sandwich-trace.sh."""
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    return subprocess.run(
        ["bash", "-c", script],
        capture_output=True, text=True, env=full_env
    )


def test_audit_complete_gate_one_of_two_incomplete():
    """1 of 2 legs written -> assert_audit_complete returns non-zero + names missing."""
    with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as f:
        log = f.name
    try:
        script = f"""
source {_TRACE_SH}
write_audit_leg_trace probabilistic my-skill {log}
# prose not written — 1 of 2
assert_audit_complete my-skill {log}
"""
        result = _run_bash(script)
        assert result.returncode != 0, (
            f"Expected non-zero (incomplete), got 0.\nstdout={result.stdout!r}\nstderr={result.stderr!r}"
        )
        combined = result.stdout + result.stderr
        assert "prose" in combined, (
            f"Expected missing leg 'prose' named in output, got:\n{combined!r}"
        )
        # The PRESENT leg must NOT be in the missing list (else a
        # regress-to-always-missing-all would pass this test silently).
        missing_line = [ln for ln in combined.splitlines() if "missing legs" in ln]
        assert missing_line, f"no 'missing legs' line in output:\n{combined!r}"
        assert "probabilistic" not in missing_line[0], f"probabilistic wrongly listed missing: {missing_line[0]!r}"
    finally:
        os.unlink(log)


def test_audit_complete_gate_no_prefix_collision():
    """A trace for skill=my-skill-extended must NOT satisfy assert_audit_complete
    for skill=my-skill (prefix-collision guard — skill= is EOL-anchored)."""
    with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as f:
        log = f.name
    try:
        script = f"""
source {_TRACE_SH}
write_audit_leg_trace probabilistic my-skill-extended {log}
write_audit_leg_trace prose         my-skill-extended {log}
# my-skill itself has ZERO legs — only my-skill-extended is complete.
assert_audit_complete my-skill {log}
"""
        result = _run_bash(script)
        assert result.returncode != 0, (
            "prefix collision: my-skill matched my-skill-extended traces.\n"
            f"stdout={result.stdout!r}\nstderr={result.stderr!r}"
        )
        combined = result.stdout + result.stderr
        # both legs missing for my-skill
        for leg in ("probabilistic", "prose"):
            assert leg in combined, f"expected {leg} missing for my-skill, got:\n{combined!r}"
    finally:
        os.unlink(log)


def test_audit_complete_gate_two_of_two_complete():
    """2 of 2 legs written -> assert_audit_complete returns 0."""
    with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as f:
        log = f.name
    try:
        script = f"""
source {_TRACE_SH}
write_audit_leg_trace probabilistic my-skill {log}
write_audit_leg_trace prose         my-skill {log}
assert_audit_complete my-skill {log}
"""
        result = _run_bash(script)
        assert result.returncode == 0, (
            f"Expected 0 (complete), got {result.returncode}.\nstdout={result.stdout!r}\nstderr={result.stderr!r}"
        )
    finally:
        os.unlink(log)


def test_audit_complete_gate_zero_of_two_incomplete():
    """No legs written -> assert_audit_complete returns non-zero + names both legs."""
    with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as f:
        log = f.name
    try:
        script = f"""
source {_TRACE_SH}
assert_audit_complete my-skill {log}
"""
        result = _run_bash(script)
        assert result.returncode != 0, (
            f"Expected non-zero (incomplete), got 0.\nstdout={result.stdout!r}\nstderr={result.stderr!r}"
        )
        combined = result.stdout + result.stderr
        assert "probabilistic" in combined, f"Expected 'probabilistic' named, got:\n{combined!r}"
        assert "prose" in combined, f"Expected 'prose' named, got:\n{combined!r}"
    finally:
        os.unlink(log)


def test_write_audit_leg_trace_format():
    """write_audit_leg_trace appends a line with gate=audit-leg, leg=, skill= fields."""
    with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as f:
        log = f.name
    try:
        script = f"""
source {_TRACE_SH}
write_audit_leg_trace probabilistic my-skill {log}
"""
        result = _run_bash(script)
        assert result.returncode == 0, f"write_audit_leg_trace failed: {result.stderr!r}"
        content = Path(log).read_text()
        assert "gate=audit-leg" in content, f"Expected 'gate=audit-leg' in log, got: {content!r}"
        assert "leg=probabilistic" in content, f"Expected 'leg=probabilistic' in log, got: {content!r}"
        assert "skill=my-skill" in content, f"Expected 'skill=my-skill' in log, got: {content!r}"
    finally:
        os.unlink(log)
