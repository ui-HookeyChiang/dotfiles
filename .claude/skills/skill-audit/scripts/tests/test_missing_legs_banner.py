"""missing_legs_banner unit tests — 2-leg contract (task-4).

Tests the pure helper missing_legs_banner(legs_ran: set[str]) -> str | None:
  - empty set -> banner string naming both legs (probabilistic, prose)
  - full 2-set -> None (no banner needed)
  - partial set -> banner names the missing leg
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parents[1]
_SKILL_AUDIT_PY = _SCRIPTS / "skill-audit.py"

_spec = importlib.util.spec_from_file_location("skill_audit_mod", str(_SKILL_AUDIT_PY))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)


def test_missing_legs_banner_empty_set_names_both():
    """missing_legs_banner(set()) must name both legs: probabilistic, prose."""
    result = _mod.missing_legs_banner(set())
    assert result is not None, "empty set -> banner expected, got None"
    assert "probabilistic" in result, f"Expected 'probabilistic' in banner, got: {result!r}"
    assert "prose" in result, f"Expected 'prose' in banner, got: {result!r}"


def test_missing_legs_banner_full_set_returns_none():
    """missing_legs_banner({'probabilistic','prose'}) must return None."""
    result = _mod.missing_legs_banner({"probabilistic", "prose"})
    assert result is None, f"Full 2-set -> None expected, got: {result!r}"


def test_missing_legs_banner_names_remaining_legs():
    """Banner names the LLM legs still to dispatch (NOTE phrasing)."""
    result = _mod.missing_legs_banner(set())
    assert result is not None
    assert "dispatch the remaining LLM legs" in result, (
        f"Banner must name the remaining-legs NOTE, got: {result!r}"
    )


def test_missing_legs_banner_partial_one_missing():
    """When probabilistic ran, the missing-legs list names only prose."""
    result = _mod.missing_legs_banner({"probabilistic"})
    assert result is not None
    # The missing-legs list is the segment between "complete:" and the period
    # before the static "Run ..." help tail.
    missing_list = result.split("complete:")[1].split(".")[0]
    assert "prose" in missing_list
    assert "probabilistic" not in missing_list
