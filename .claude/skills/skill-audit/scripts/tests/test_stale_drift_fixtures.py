"""Structural integrity test for the stale-drift canary fixture.

Does NOT run the LLM. Verifies the red (must-fire) + green (must-not-fire)
cases coexist in one fixture skill, that the absent-script claim names a
script that truly does not exist, and that the live-referent claim names a
script that does.
"""
from pathlib import Path

FIXTURE = Path(__file__).parent / "fixtures" / "stale-drift-skill"


def test_fixture_skill_exists():
    assert (FIXTURE / "SKILL.md").is_file()
    assert (FIXTURE / "scripts" / "real_gate.py").is_file()


def test_red_assertion_names_an_absent_script():
    text = (FIXTURE / "SKILL.md").read_text()
    # red case A: asserts scripts/validate.py which must NOT exist
    assert "scripts/validate.py" in text
    assert not (FIXTURE / "scripts" / "validate.py").exists()


def test_green_case_has_live_referent_and_external_line():
    text = (FIXTURE / "SKILL.md").read_text()
    # green case: names real_gate.py which DOES exist
    assert "real_gate.py" in text
    # external-shape line that must NOT fire
    assert "gh pr merge" in text
