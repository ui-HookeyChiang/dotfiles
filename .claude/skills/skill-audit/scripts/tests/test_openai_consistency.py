"""Tests for Rules 8a-8d: openai.yaml consistency detector."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from syntax_audit import (  # noqa: E402
    Finding,
    detect_openai_yaml_consistency,
    _build_parsed_context,
)

FIXTURES = Path(__file__).parent / "fixtures" / "openai_consistency"


def _run_on(name: str) -> list[Finding]:
    """Run the detector on fixtures/openai_consistency/<name>/SKILL.md."""
    skill_md = FIXTURES / name / "SKILL.md"
    skill_dir = skill_md.parent
    content = skill_md.read_text()
    ctx = _build_parsed_context(content)
    return detect_openai_yaml_consistency(skill_dir, ctx)


# --- Rule 8a: agents/openai.yaml missing ------------------------------------

def test_8a_missing_yaml_high():
    fs = _run_on("missing_yaml")
    found = [f for f in fs if f.severity == "HIGH" and "8a" in f.summary]
    assert found, f"Expected Rule 8a HIGH finding, got: {fs}"
    assert found[0].kind == "F"


# --- Rule 8b: fm disable-model-invocation but yaml lacks policy -------------

def test_8b_policy_missing_high():
    fs = _run_on("policy_missing")
    found = [f for f in fs if f.severity == "HIGH" and "8b" in f.summary]
    assert found, f"Expected Rule 8b HIGH finding, got: {fs}"
    assert found[0].kind == "F"


# --- Rule 8c: yaml has allow_implicit_invocation: false, fm lacks flag ------

def test_8c_policy_extra_high():
    fs = _run_on("policy_extra")
    found = [f for f in fs if f.severity == "HIGH" and "8c" in f.summary]
    assert found, f"Expected Rule 8c HIGH finding, got: {fs}"
    assert found[0].kind == "F"


# --- Rule 8d: yaml exists but display_name empty ----------------------------

def test_8d_empty_metadata_low():
    fs = _run_on("empty_metadata")
    found = [f for f in fs if f.severity == "LOW" and "8d" in f.summary]
    assert found, f"Expected Rule 8d LOW finding, got: {fs}"
    assert found[0].kind == "F"


# --- Clean fixture: no findings ---------------------------------------------

def test_ok_no_findings():
    fs = _run_on("ok")
    assert fs == [], f"Expected no findings for ok fixture, got: {fs}"


# --- 8a short-circuits remaining rules --------------------------------------

def test_8a_returns_only_one_finding():
    """When yaml is missing, only 8a is emitted (no 8b/8c/8d)."""
    fs = _run_on("missing_yaml")
    assert len(fs) == 1, f"Expected exactly 1 finding (8a only), got: {fs}"
