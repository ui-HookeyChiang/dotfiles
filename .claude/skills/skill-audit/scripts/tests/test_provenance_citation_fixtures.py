"""Structural integrity test for the provenance_citation fixture set.

This does NOT exercise the LLM advisory pass. It only verifies the
expected positive + negative fixtures exist, are non-empty, and start
with a markdown YAML frontmatter block.
"""
import pytest
from pathlib import Path


FIXTURES_DIR = Path(__file__).parent / "fixtures" / "provenance_citation"

EXPECTED_FILES = {
    "positive_per_spec_path.md",
    "positive_amendment_aside.md",
    "negative_bare_navigation_link.md",
    "negative_external_rfc_amendment.md",
    "negative_inline_contract_spec.md",
}


def test_fixture_directory_exists():
    assert FIXTURES_DIR.is_dir(), f"missing fixtures dir: {FIXTURES_DIR}"


def test_expected_fixture_files_present():
    actual = {p.name for p in FIXTURES_DIR.glob("*.md")}
    missing = EXPECTED_FILES - actual
    unexpected = actual - EXPECTED_FILES
    assert not missing, f"missing fixture files: {sorted(missing)}"
    assert not unexpected, (
        f"unexpected fixture files (update EXPECTED_FILES if intentional): "
        f"{sorted(unexpected)}"
    )


@pytest.mark.parametrize("name", sorted(EXPECTED_FILES))
def test_fixture_has_frontmatter(name):
    text = (FIXTURES_DIR / name).read_text()
    assert text.startswith("---\n"), f"{name}: missing leading frontmatter delimiter"
    # second '---' must appear before any '# ' heading
    closing = text.find("\n---\n", 4)
    assert closing > 0, f"{name}: unterminated frontmatter block"
    first_h1 = text.find("\n# ")
    assert first_h1 > closing, f"{name}: H1 appears before frontmatter close"
