from __future__ import annotations

from pathlib import Path

import semantic_audit


REPO_ROOT = Path(__file__).resolve().parents[3]


def test_semantic_axes_documented_in_skill_and_detectors_reference() -> None:
    """Guard against live semantic axes drifting out of prose docs."""
    docs = {
        "SKILL.md": (REPO_ROOT / "skill-audit" / "SKILL.md").read_text(encoding="utf-8"),
        "references/detectors.md": (
            REPO_ROOT / "skill-audit" / "references" / "detectors.md"
        ).read_text(encoding="utf-8"),
    }

    for axis in semantic_audit.AXES:
        for name, text in docs.items():
            assert axis in text, f"{axis} missing from {name}"
