"""Tests for audit.py CLI flag validation."""
import subprocess
import sys
from pathlib import Path

AUDIT_PY = Path(__file__).resolve().parents[1] / "syntax_audit.py"
SKILL_MD = Path(__file__).resolve().parents[2] / "SKILL.md"


def _run(args):
    r = subprocess.run([sys.executable, str(AUDIT_PY), *args],
                       capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def test_advisory_with_write_spec_errors():
    """--metrics + --write-spec must error (mutually exclusive)."""
    rc, out, err = _run([str(SKILL_MD), "--metrics", "--write-spec"])
    assert rc == 1
    assert "mutually exclusive" in err or "mutually exclusive" in out


def test_json_alone_errors():
    """--json without --metrics/--with-llm/--rank-all must error."""
    rc, out, err = _run([str(SKILL_MD), "--json"])
    assert rc == 1
    assert "requires" in err or "requires" in out


def test_json_with_metrics_ok():
    """--json --metrics is valid (no flag error)."""
    rc, out, err = _run([str(SKILL_MD), "--metrics", "--json"])
    # rc may be 0 or 2 (composite-dependent); the test is that it didn't ERROR-1 with a flag complaint
    assert rc in (0, 2), f"unexpected exit {rc}: {err}"



# ---------------------------------------------------------------------------
# PR #501 — bare invocation routes to advisory + LLM by default;
# --no-llm suppresses LLM; harness-missing falls back gracefully.

def test_bare_invocation_routes_to_advisory_and_attempts_llm():
    """No flags on a single-skill audit => advisory mode, LLM dispatch deferred.

    From the CLI _make_spawn() returns None (LLM dispatch is the main agent's
    responsibility per SKILL.md ## LLM advisory step). The policy is: emit a
    stderr note and fall back to metrics-only output. Exit code follows
    composite-vs-threshold (not 1). For skill-syntax-audit itself,
    composite < 30 => exit 2.
    """
    rc, out, err = _run([str(SKILL_MD)])
    assert rc in (0, 2), f"unexpected exit {rc}: stderr={err}"
    # Advisory-mode report (not legacy "skill-syntax-audit report:" header).
    assert "advisory report" in out, f"expected advisory report header, got: {out[:200]}"
    # Stderr note announcing LLM dispatch deferred to main agent.
    assert "LLM dispatch deferred to main agent" in err and "falling back" in err, (
        f"expected deferred-dispatch note on stderr, got: {err!r}"
    )
    # Mode label reflects fallback path (so callers can distinguish).
    assert "metrics-llm-fallback" in out


def test_no_llm_suppresses_llm_dispatch():
    """--no-llm runs advisory metrics-only; no LLM dispatched, no warning."""
    rc, out, err = _run([str(SKILL_MD), "--no-llm"])
    assert rc in (0, 2), f"unexpected exit {rc}: stderr={err}"
    assert "advisory report" in out
    # No LLM was attempted, so no harness-fallback warning.
    assert "LLM unavailable" not in err, (
        f"--no-llm should not attempt LLM, but warning appeared: {err!r}"
    )
    # Mode label is the plain metrics path (not -with-llm, not -fallback).
    assert "**Mode**: metrics" in out
    assert "metrics-llm-fallback" not in out
    assert "metrics-with-llm" not in out


def test_no_llm_and_with_llm_are_mutually_exclusive():
    """--no-llm + --with-llm is a contradiction; must error with rc=1."""
    rc, out, err = _run([str(SKILL_MD), "--no-llm", "--with-llm"])
    assert rc == 1
    assert "conflicts" in err or "conflicts" in out


def test_metrics_remains_synonym_of_no_llm():
    """--metrics (legacy advisory flag) keeps working as a --no-llm synonym."""
    rc, out, err = _run([str(SKILL_MD), "--metrics"])
    assert rc in (0, 2), f"unexpected exit {rc}: stderr={err}"
    assert "advisory report" in out
    assert "LLM unavailable" not in err
    assert "**Mode**: metrics" in out


def test_legacy_path_still_reachable_via_write_spec():
    """--write-spec keeps invoking legacy detectors (byte-identical path)."""
    rc, out, err = _run([str(SKILL_MD), "--write-spec"])
    # skill-syntax-audit on itself has no findings under legacy detectors => exit 2.
    assert rc in (0, 2), f"unexpected exit {rc}: stderr={err}"
    # Legacy-mode report header (no "advisory" word).
    assert "skill-audit report:" in out
    assert "advisory report" not in out
