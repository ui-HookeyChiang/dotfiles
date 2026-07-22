"""Pytest cases for the task-2 semantic_axis validator extension.

Each test invokes ``validate-findings.sh`` against one of the four fixture
YAML files under ``fixtures/v2/`` and asserts the expected exit code +
drop-reason substring.

The fixtures exercise both new validator branches:

* paragraph-class finding without ``semantic_axis: G7`` → drop.
* non-paragraph-class finding with ``semantic_axis`` set → drop.

A regression case runs the pre-existing seeded v2 fixture to confirm the
new checks do not affect lexical/meta/hedge batches.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SKILL_ROOT = REPO_ROOT / "prose-guidelines"
VALIDATOR = SKILL_ROOT / "scripts" / "validate-findings.sh"
FIXTURES = SKILL_ROOT / "scripts" / "tests" / "fixtures" / "v2"
TARGET = FIXTURES / "semantic_axis_target.md"

SEEDED_YAML = SKILL_ROOT / "tests" / "fixtures" / "seeded-v2-agent-output.yaml"
SEEDED_TARGET = SKILL_ROOT / "tests" / "fixtures" / "seeded-v2-baseline.md"


def _run(yaml_path: Path, target_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(VALIDATOR), str(yaml_path), str(target_path)],
        capture_output=True,
        text=True,
        check=False,
    )


# --- positive cases -------------------------------------------------------


def test_paragraph_with_semantic_axis_valid_passes() -> None:
    res = _run(FIXTURES / "paragraph_with_semantic_axis_valid.yaml", TARGET)
    assert res.returncode == 0, f"expected exit 0, got {res.returncode}; stderr={res.stderr!r}"
    assert "semantic_axis" not in res.stderr, f"unexpected semantic_axis drop: {res.stderr!r}"


def test_lexical_no_semantic_axis_valid_passes() -> None:
    res = _run(FIXTURES / "lexical_no_semantic_axis_valid.yaml", TARGET)
    assert res.returncode == 0, f"expected exit 0, got {res.returncode}; stderr={res.stderr!r}"
    assert "semantic_axis" not in res.stderr, f"unexpected semantic_axis drop: {res.stderr!r}"


# --- negative cases -------------------------------------------------------


def test_paragraph_missing_semantic_axis_drops() -> None:
    res = _run(FIXTURES / "paragraph_missing_semantic_axis.yaml", TARGET)
    assert res.returncode == 1, f"expected exit 1, got {res.returncode}; stderr={res.stderr!r}"
    assert "paragraph class missing semantic_axis: G7" in res.stderr, res.stderr
    assert "batch invalidated" in res.stderr, res.stderr


def test_lexical_with_semantic_axis_drops() -> None:
    res = _run(FIXTURES / "lexical_with_semantic_axis.yaml", TARGET)
    assert res.returncode == 1, f"expected exit 1, got {res.returncode}; stderr={res.stderr!r}"
    assert "semantic_axis only valid for paragraph class, got lexical" in res.stderr, res.stderr
    assert "batch invalidated" in res.stderr, res.stderr


# --- regression -----------------------------------------------------------


def test_seeded_v2_fixture_still_passes() -> None:
    """Existing v2 seeded fixture (lexical/meta/hedge only) must not regress."""
    res = _run(SEEDED_YAML, SEEDED_TARGET)
    assert res.returncode == 0, f"seeded v2 regression: exit={res.returncode}; stderr={res.stderr!r}"
    # The two pre-existing intentional malformed drops must remain; no new
    # semantic_axis-related drops should appear.
    assert "semantic_axis" not in res.stderr, f"unexpected semantic_axis drop: {res.stderr!r}"
