"""G1 cross-skill duplication detector — pure-logic tests (Task 4a / #15).

Scope: parser, pairwise loop, severity boundary, YAML schema, corpus_dir
loader, edge cases. Real LLM mocked via ``unittest.mock.patch``; testdata
fixtures (Task 4c / #22) deferred — paragraphs inlined to ``tmp_path``.

Assertions derive from upstream contracts in ``finding-schema.md`` and
``severity-rubric.md`` (Task 1a/1b), not from detector internals.
"""
from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

_SCRIPTS = Path(__file__).resolve().parents[1]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from detectors import g1_cross_skill_dup as g1  # noqa: E402

PARAPHRASED = {"is_paraphrased": True, "confidence": "medium"}
NOT_PARAPHRASED = {"is_paraphrased": False, "confidence": "low"}


def _long_para(label: str, lines: int = 6, words_per_line: int = 8) -> str:
    """Build a >=30-word paragraph; ``lines`` controls line_count."""
    body = " ".join(f"{label}word{i}" for i in range(words_per_line))
    return "\n".join(f"{body} L{i}" for i in range(lines))


def _write(tmp: Path, name: str, *paragraphs: str) -> str:
    p = tmp / name
    p.write_text("\n\n".join(paragraphs) + "\n", encoding="utf-8")
    return str(p)


# ---- module & parser --------------------------------------------------------

def test_module_importable_and_exports_detect():
    assert callable(g1.detect)
    assert callable(g1._call_llm)
    assert hasattr(g1, "Paragraph")


def test_parser_records_line_offsets_and_word_count(tmp_path):
    f = _write(tmp_path, "a.md", "# Header", _long_para("a"))
    candidates = [p for p in g1._parse_paragraphs(f) if p.is_candidate]
    assert candidates
    c = candidates[0]
    assert c.line_count == 6
    assert c.word_count >= g1.MIN_CANDIDATE_WORDS
    assert c.start_line >= 1 and c.end_line >= c.start_line


def test_parser_skips_fenced_code_blocks(tmp_path):
    f = tmp_path / "c.md"
    f.write_text(
        _long_para("real") + "\n\n```python\n"
        + "\n".join(f"fake line {i}" for i in range(30))
        + "\n```\n\n" + _long_para("after"),
        encoding="utf-8",
    )
    texts = [p.text for p in g1._parse_paragraphs(str(f)) if p.is_candidate]
    assert len(texts) == 2
    assert not any("fake line" in t for t in texts)


# ---- pairwise loop ----------------------------------------------------------

def test_default_stub_emits_zero_findings(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("shared"))
    b = _write(tmp_path, "b.md", _long_para("shared"))
    assert g1.detect([a, b]) == []


def test_no_llm_short_circuits(tmp_path):
    """--no-llm skips LLM phase and returns an explicit N/A advisory.

    Old contract: bare [].
    New contract (§6 case-3 fail-loud): returns a list with one N/A advisory
    so the caller knows the axis was skipped, not that the file is clean.
    No real findings (id starting 'g1-0') must appear."""
    a = _write(tmp_path, "a.md", _long_para("shared"))
    b = _write(tmp_path, "b.md", _long_para("shared"))
    with patch.object(g1, "_call_llm", return_value=PARAPHRASED):
        result = g1.detect([a, b], no_llm=True)
    # Must not be bare []; must contain N/A advisory, no real findings
    real = [f for f in result if not f.get("not_applicable")]
    assert real == [], f"no real findings in --no-llm mode, got: {real}"
    na = [f for f in result if f.get("not_applicable")]
    assert na, "must return at least one N/A advisory in --no-llm mode"


# ---- severity boundaries (severity-rubric.md L9-14) -------------------------

def test_severity_3_skills_is_HIGH(tmp_path):
    paths = [_write(tmp_path, f"{n}.md", _long_para("x")) for n in "abc"]
    with patch.object(g1, "_call_llm", return_value=PARAPHRASED):
        findings = g1.detect(paths)
    assert len(findings) == 1
    assert findings[0]["severity"] == "HIGH"
    assert findings[0]["confidence"] == "high"


def test_severity_2_skills_10_lines_is_MED(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x", lines=10))
    b = _write(tmp_path, "b.md", _long_para("x", lines=10))
    with patch.object(g1, "_call_llm", return_value=PARAPHRASED):
        findings = g1.detect([a, b])
    assert len(findings) == 1 and findings[0]["severity"] == "MED"
    assert findings[0]["confidence"] == "medium"


def test_severity_2_skills_9_lines_is_LOW(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x", lines=9))
    b = _write(tmp_path, "b.md", _long_para("x", lines=9))
    with patch.object(g1, "_call_llm", return_value=PARAPHRASED):
        findings = g1.detect([a, b])
    assert len(findings) == 1 and findings[0]["severity"] == "LOW"


# ---- corpus_dir loader ------------------------------------------------------

def test_corpus_dir_appends_md_files(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("a"))
    b = _write(tmp_path, "b.md", _long_para("b"))
    corpus = tmp_path / "corpus"
    corpus.mkdir()
    _write(corpus, "c.md", _long_para("c"))
    _write(corpus, "d.md", _long_para("d"))
    expanded = g1._expand_corpus([a, b], str(corpus))
    assert len(expanded) == 4
    assert sum(1 for p in expanded if p.endswith("c.md")) == 1
    assert sum(1 for p in expanded if p.endswith("d.md")) == 1


def test_corpus_dir_invalid_raises(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("a"))
    b = _write(tmp_path, "b.md", _long_para("b"))
    with pytest.raises(ValueError, match="corpus_dir not a directory"):
        g1.detect([a, b], corpus_dir=str(tmp_path / "nope"))


# ---- finding schema (finding-schema.md) -------------------------------------

REQUIRED_FIELDS = {
    "id", "axis", "severity", "confidence", "title", "summary",
    "locations", "evidence_quote", "suggested_action", "requires_human",
    "numeric_basis",
}


def test_finding_schema_required_fields_present(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    with patch.object(g1, "_call_llm", return_value=PARAPHRASED):
        findings = g1.detect([a, b])
    assert findings
    f = findings[0]
    assert not REQUIRED_FIELDS - set(f.keys())
    assert f["id"].startswith("g1-")
    assert f["axis"] == "G1"
    assert f["severity"] in ("HIGH", "MED", "LOW")
    assert f["confidence"] in ("high", "medium", "low")
    assert isinstance(f["locations"], list) and f["locations"]
    for loc in f["locations"]:
        assert set(loc.keys()) == {"file", "lines"}
        assert loc["lines"].startswith("L") and "-L" in loc["lines"]
    assert f["numeric_basis"] is None
    assert f["requires_human"] is True


def test_finding_yaml_serializable(tmp_path):
    yaml = pytest.importorskip("yaml")
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    with patch.object(g1, "_call_llm", return_value=PARAPHRASED):
        findings = g1.detect([a, b])
    reparsed = yaml.safe_load(yaml.safe_dump({"findings": findings}))
    assert reparsed["findings"][0]["axis"] == "G1"


# ---- edge cases -------------------------------------------------------------

def test_single_path_raises_value_error(tmp_path):
    # A single file with only 1 candidate paragraph raises ValueError
    # (needs >= 2 candidates for self-compare to be meaningful).
    a = _write(tmp_path, "a.md", _long_para("x"))
    with pytest.raises(ValueError, match="needs >= 2 candidate paragraphs"):
        g1.detect([a])


def test_paragraphs_under_30_words_raises_value_error(tmp_path):
    # Files with only sub-30-word paragraphs produce 0 candidates → ValueError.
    a = _write(tmp_path, "a.md", "tiny short paragraph")
    b = _write(tmp_path, "b.md", "tiny short paragraph")
    with pytest.raises(ValueError, match="needs >= 2 candidate paragraphs"):
        g1.detect([a, b])


def test_long_paragraphs_do_reach_llm(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    seen: list = []
    def spy(pa, pb):
        seen.append((pa, pb))
        return NOT_PARAPHRASED
    with patch.object(g1, "_call_llm", side_effect=spy):
        g1.detect([a, b])
    assert len(seen) == 1


def test_cross_file_finding_spans_two_files(tmp_path):
    """Cross-skill finding must cite >= 2 files.
    Both files use label 'x' so the Jaccard prefilter passes (Jaccard=1.0).
    """
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    with patch.object(g1, "_call_llm", return_value=PARAPHRASED):
        findings = g1.detect([a, b])
    assert findings
    for f in findings:
        assert len({loc["file"] for loc in f["locations"]}) >= 2


# ── RED: G1 --no-llm must return explicit N/A label, not bare [] ──────────────
# §6 case-3: cross-skill semantic dup is an OPEN concept — no deterministic heuristic
# covers the open set. Returning bare [] in --no-llm mode is fail-silent (the caller
# cannot distinguish "no dups found" from "axis not run"). Correct contract: return
# an explicit N/A indicator so the caller knows the axis was skipped (fail-loud).

def test_no_llm_g1_returns_explicit_na_label(tmp_path):
    """--no-llm must return an explicit N/A advisory, not bare [].

    An open-concept detector that returns [] in --no-llm mode is fail-silent —
    the caller cannot tell whether zero findings means 'clean' or 'not run'.
    The new contract: detect() returns a list containing at least one dict entry
    with a recognisable N/A marker (axis=='G1', id contains 'na' or 'not_applicable',
    or a special sentinel field)."""
    a = _write(tmp_path, "a.md", _long_para("shared"))
    b = _write(tmp_path, "b.md", _long_para("shared"))
    with patch.object(g1, "_call_llm", return_value=PARAPHRASED):
        result = g1.detect([a, b], no_llm=True)
    # NEW contract: must NOT be bare []; must contain an N/A advisory entry
    assert result != [], (
        "G1 --no-llm must return an explicit N/A advisory, not bare [] "
        "(fail-loud: caller must know axis was not run, not that result is clean)"
    )
    # The N/A entry must be clearly labeled
    na_entry = next(
        (f for f in result if isinstance(f, dict) and (
            "not_applicable" in str(f.get("id", "")).lower()
            or "n/a" in str(f.get("id", "")).lower()
            or f.get("severity") == "NOT_APPLICABLE"
            or "not_applicable" in str(f.get("confidence", "")).lower()
            or f.get("not_applicable") is True
        )),
        None,
    )
    assert na_entry is not None, (
        f"G1 --no-llm result must contain an N/A advisory entry. Got: {result}"
    )
