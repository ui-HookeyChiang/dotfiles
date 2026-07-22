"""Tests for the minimal YAML parser used by advisory LLM dispatch."""
import pytest
from advisory.yaml_lite import parse_yaml, YamlParseError


def test_empty_document():
    assert parse_yaml("") == {}


def test_top_level_keys_with_empty_lists():
    text = """\
paraphrased_redundancy: []
contradictions: []
"""
    assert parse_yaml(text) == {
        "paraphrased_redundancy": [],
        "contradictions": [],
    }


def test_list_of_mappings():
    text = """\
paraphrased_redundancy:
  - locations: [62-64, 249-251]
    summary: "AWS DryRun verification appears in 3 sections"
    severity: MED
    refactor: "extract scripts/verify-aws-signer.sh"
    saved_lines: 10
"""
    got = parse_yaml(text)
    assert got["paraphrased_redundancy"] == [{
        "locations": ["62-64", "249-251"],
        "summary": "AWS DryRun verification appears in 3 sections",
        "severity": "MED",
        "refactor": "extract scripts/verify-aws-signer.sh",
        "saved_lines": 10,
    }]


def test_multiple_top_level_lists():
    text = """\
paraphrased_redundancy:
  - locations: [10-20]
    summary: "first"
    severity: LOW
contradictions:
  - locations: [30-40, 50-60]
    summary: "second"
    severity: HIGH
"""
    got = parse_yaml(text)
    assert "paraphrased_redundancy" in got
    assert "contradictions" in got
    assert got["paraphrased_redundancy"][0]["summary"] == "first"
    assert got["contradictions"][0]["severity"] == "HIGH"


def test_malformed_indentation_raises():
    text = """\
paraphrased_redundancy:
- locations: [1-2]
  summary: bad indent
"""
    with pytest.raises(YamlParseError):
        parse_yaml(text)


def test_unquoted_string_value():
    text = "severity: HIGH\n"
    assert parse_yaml(text) == {"severity": "HIGH"}


def test_integer_value():
    text = "saved_lines: 42\n"
    assert parse_yaml(text) == {"saved_lines": 42}


def test_bracket_list_of_strings():
    text = "locations: [62-64, 249-251, 568]\n"
    assert parse_yaml(text) == {"locations": ["62-64", "249-251", "568"]}


def test_quoted_string_with_special_chars():
    text = 'summary: "has: colons and # hash"\n'
    assert parse_yaml(text) == {"summary": "has: colons and # hash"}


def test_empty_scalar_value_returns_none():
    """`severity:` followed by next top-level key returns None, not []."""
    text = "severity:\nseverity_next: HIGH\n"
    got = parse_yaml(text)
    assert got == {"severity": None, "severity_next": "HIGH"}


def test_empty_scalar_value_at_eof_returns_none():
    text = "severity:\n"
    assert parse_yaml(text) == {"severity": None}


def test_error_line_number_accounts_for_comments_and_blanks():
    """`# comment\n\n\nbad_line` — error should say line 4, not line 1."""
    text = "# comment\n\n\nbad line here\n"
    try:
        parse_yaml(text)
    except YamlParseError as e:
        assert "line 4" in str(e), f"got: {e}"
    else:
        raise AssertionError("expected YamlParseError")
