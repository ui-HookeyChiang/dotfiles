from __future__ import annotations

from pathlib import Path

from detectors import good_classes as gc


def _write_skill(tmp_path: Path, body: str) -> Path:
    skill = tmp_path / "example" / "SKILL.md"
    skill.parent.mkdir()
    skill.write_text(
        "---\n"
        "name: example\n"
        "description: Test fixture. Use when validating good classes.\n"
        "---\n\n"
        "# Example\n\n"
        f"{body}\n",
        encoding="utf-8",
    )
    return skill


def test_flags_out_of_class_history_section(tmp_path: Path) -> None:
    skill = _write_skill(
        tmp_path,
        "## Historical Notes\n\n"
        "The project began as an experiment during a planning cycle. The team "
        "debated several alternatives and eventually settled on the current "
        "shape after many conversations, but this narrative does not tell an "
        "agent anything operational. It is background context about team "
        "history, preferences, and the mood of an old planning meeting.\n",
    )

    findings = gc.detect([str(skill)])

    assert len(findings) == 1
    assert findings[0]["axis"] == "GC"
    assert findings[0]["severity"] == "LOW"
    assert "Historical Notes" in findings[0]["title"]


def test_silent_on_conformant_sections(tmp_path: Path) -> None:
    skill = _write_skill(
        tmp_path,
        "## Run\n\n"
        "```bash\n"
        "python3 scripts/check.py <target>\n"
        "```\n\n"
        "Exit code: `0` clean, `1` error.\n\n"
        "## Preconditions\n\n"
        "Only run this after the target directory exists. Stop if `SKILL.md` "
        "is missing.\n\n"
        "## Not This Skill\n\n"
        "- Numeric scoring -> `darwin-skill`.\n"
        "- Prose density only -> `prose-guidelines`.\n",
    )

    assert gc.detect([str(skill)]) == []
