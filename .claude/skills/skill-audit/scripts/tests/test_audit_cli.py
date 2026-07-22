"""audit.py CLI — integration tests (Task 5 / #16).

Scope: exit-code contract (0/2/1), three-axis aggregation, --axis filter,
--no-llm passthrough, RuntimeError -> exit 1.  Every
detector call is mocked at the import surface (``detectors.gN.detect``)
so no real LLM API is invoked.

Exit-code resolution is the central contract — three values are exercised:
    0 (EXIT_FLAGGED) — at least one detector returned a finding
    2 (EXIT_CLEAN)   — all detectors returned []
    1 (EXIT_FAILURE) — any detector raised RuntimeError / NotImplementedError
                       / returned a non-list, or input not found / G1 ValueError
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

_SCRIPTS = Path(__file__).resolve().parents[1]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

import semantic_audit as audit  # noqa: E402
from detectors import (  # noqa: E402
    g1_cross_skill_dup as g1,
    g8_progressive_disclosure as g8,
)


def _make_skill_md(tmp_path: Path, name: str = "flow-dev/SKILL.md") -> Path:
    skill = tmp_path / name
    skill.parent.mkdir(parents=True, exist_ok=True)
    skill.write_text("# A SKILL.md\n\nbody.\n", encoding="utf-8")
    return skill


def _finding(axis: str, severity: str = "MED", idx: int = 1) -> dict:
    return {
        "id": f"{axis.lower()}-{idx:03d}",
        "axis": axis,
        "severity": severity,
        "confidence": "medium",
        "title": f"{axis} mock",
        "summary": "mock summary",
        "locations": [{"file": "x", "lines": "L1-L5"}],
        "evidence_quote": "mock",
        "numeric_basis": None,
        "suggested_action": "do thing",
        "requires_human": True,
    }


# ---- exit-code contract: 0 / 2 / 1 -----------------------------------------

def test_exit_0_when_any_finding_emitted(tmp_path):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", return_value=[_finding("G1")]), \
         patch.object(g8, "detect", return_value=[]):
        rc = audit.main([str(skill)])
    assert rc == 0


def test_exit_2_when_all_axes_clean(tmp_path):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", return_value=[]), \
         patch.object(g8, "detect", return_value=[]):
        rc = audit.main([str(skill)])
    assert rc == 2


def test_exit_1_when_detector_raises_runtimeerror(tmp_path, capsys):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", side_effect=RuntimeError("bad llm")), \
         patch.object(g8, "detect", return_value=[]):
        rc = audit.main([str(skill)])
    assert rc == 1
    assert "RuntimeError" in capsys.readouterr().err


def test_exit_1_when_detector_raises_notimplementederror(tmp_path, capsys):
    skill = _make_skill_md(tmp_path)
    with patch.object(g8, "detect", side_effect=NotImplementedError("stub")), \
         patch.object(g1, "detect", return_value=[]):
        rc = audit.main([str(skill), "--axis", "G8"])
    assert rc == 1
    assert "not implemented" in capsys.readouterr().err.lower()


def test_exit_1_on_missing_input(capsys):
    rc = audit.main(["/no/such/file.md"])
    assert rc == 1
    assert "input not found" in capsys.readouterr().err


def test_exit_1_when_detector_returns_non_list(tmp_path, capsys):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", return_value="not a list"), \
         patch.object(g8, "detect", return_value=[]):
        rc = audit.main([str(skill)])
    assert rc == 1
    assert "non-list" in capsys.readouterr().err


# ---- axis routing ----------------------------------------------------------

def test_axis_all_invokes_both_detectors(tmp_path):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", return_value=[]) as m_g1, \
         patch.object(g8, "detect", return_value=[]) as m_g8:
        audit.main([str(skill), "--axis", "all"])
    assert m_g1.called and m_g8.called


def test_default_axis_runs_all_remaining(tmp_path):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", return_value=[]) as m_g1, \
         patch.object(g8, "detect", return_value=[]) as m_g8:
        audit.main([str(skill)])
    assert m_g1.called and m_g8.called


def test_axis_G1_only_calls_g1(tmp_path):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", return_value=[]) as m_g1, \
         patch.object(g8, "detect", return_value=[]) as m_g8:
        audit.main([str(skill), "--axis", "G1"])
    assert m_g1.called
    assert not m_g8.called


def test_axis_G8_only_calls_g8(tmp_path):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", return_value=[]) as m_g1, \
         patch.object(g8, "detect", return_value=[]) as m_g8:
        audit.main([str(skill), "--axis", "G8"])
    assert not m_g1.called
    assert m_g8.called


# ---- detector-kwarg divergence: G8 receives llm_fn=, not llm_dispatch= -----

def test_g8_receives_llm_fn_kwarg_not_llm_dispatch(tmp_path):
    """audit.py absorbs the detector kwarg divergence:
       G1 gets ``llm_dispatch=``; G8 gets ``llm_fn=``.
       Tech debt, recorded; this test pins the contract."""
    skill = _make_skill_md(tmp_path)
    seen: dict = {}

    def _spy_g8(paths, **kwargs):
        seen["paths"] = list(paths)
        seen["kwargs"] = dict(kwargs)
        return []

    with patch.object(g8, "detect", side_effect=_spy_g8), \
         patch.object(g1, "detect", return_value=[]):
        audit.main([str(skill), "--axis", "G8"])

    assert "llm_fn" in seen["kwargs"]
    assert "llm_dispatch" not in seen["kwargs"]


def test_g1_receives_llm_dispatch_kwarg(tmp_path):
    skill = _make_skill_md(tmp_path)
    seen: dict = {}

    def _spy(paths, **kwargs):
        seen["kwargs"] = dict(kwargs)
        return []

    with patch.object(g1, "detect", side_effect=_spy), \
         patch.object(g8, "detect", return_value=[]):
        audit.main([str(skill), "--axis", "G1"])

    assert "llm_dispatch" in seen["kwargs"]
    assert "llm_fn" not in seen["kwargs"]


# ---- --no-llm passthrough --------------------------------------------------

def test_no_llm_flag_passes_through_to_all_detectors(tmp_path):
    skill = _make_skill_md(tmp_path)
    seen = {"g1": None, "g8": None}

    def _spy(name):
        def _inner(paths, **kwargs):
            seen[name] = kwargs.get("no_llm")
            return []
        return _inner

    with patch.object(g1, "detect", side_effect=_spy("g1")), \
         patch.object(g8, "detect", side_effect=_spy("g8")):
        audit.main([str(skill), "--no-llm"])

    assert seen == {"g1": True, "g8": True}


def test_no_llm_omitted_defaults_to_false(tmp_path):
    skill = _make_skill_md(tmp_path)
    seen = {}

    def _spy(paths, **kwargs):
        seen["no_llm"] = kwargs.get("no_llm")
        return []

    with patch.object(g1, "detect", side_effect=_spy), \
         patch.object(g8, "detect", return_value=[]):
        audit.main([str(skill), "--axis", "G1"])

    assert seen["no_llm"] is False


# ---- aggregation across axes ----------------------------------------------

def test_aggregated_findings_across_axes(tmp_path, capsys):
    skill = _make_skill_md(tmp_path)
    with patch.object(g1, "detect", return_value=[_finding("G1")]), \
         patch.object(g8, "detect", return_value=[_finding("G8", idx=3)]):
        rc = audit.main([str(skill)])
    assert rc == 0
    out = capsys.readouterr().out
    # Both finding ids appear in stdout YAML.
    assert "id: g1-001" in out
    assert "id: g8-003" in out
    assert out.startswith("findings:")


# ---- env-var llm dispatch resolution (no real network) ---------------------

def test_env_var_unset_yields_none_dispatch(tmp_path, monkeypatch):
    monkeypatch.delenv("SKILL_SEMANTIC_AUDIT_LLM_DISPATCH", raising=False)
    skill = _make_skill_md(tmp_path)
    seen = {}

    def _spy(paths, **kwargs):
        seen["llm_dispatch"] = kwargs.get("llm_dispatch")
        return []

    with patch.object(g1, "detect", side_effect=_spy), \
         patch.object(g8, "detect", return_value=[]):
        audit.main([str(skill), "--axis", "G1"])

    assert seen["llm_dispatch"] is None


def test_env_var_bad_path_falls_back_to_none(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("SKILL_SEMANTIC_AUDIT_LLM_DISPATCH",
                       "no.such.module:not_a_thing")
    skill = _make_skill_md(tmp_path)
    seen = {}

    def _spy(paths, **kwargs):
        seen["llm_dispatch"] = kwargs.get("llm_dispatch")
        return []

    with patch.object(g1, "detect", side_effect=_spy), \
         patch.object(g8, "detect", return_value=[]):
        audit.main([str(skill), "--axis", "G1"])

    assert seen["llm_dispatch"] is None
    assert "no-LLM" in capsys.readouterr().err


# ---- G7 removal contract (spec 2026-05-29-prose-guidelines-g7-dedup) ---------

def test_g7_not_in_axis_choices():
    """G7 axis was removed in 2026-05-29 — paragraph density moved to
    `prose-guidelines`. The CLI must no longer accept --axis G7 as a valid
    choice."""
    assert "G7" not in audit._AXIS_CHOICES
    assert "G7" not in audit.AXES


def test_axis_G7_exits_1_with_redirect_message(tmp_path, capsys):
    """User passing --axis G7 gets a hard error pointing at
    `prose-guidelines`. Exit 1, stderr mentions prose-guidelines."""
    skill = _make_skill_md(tmp_path)
    with pytest.raises(SystemExit) as exc_info:
        audit.main([str(skill), "--axis", "G7"])
    assert exc_info.value.code == 1
    err = capsys.readouterr().err
    assert "prose-guidelines" in err
    assert "G7" in err
