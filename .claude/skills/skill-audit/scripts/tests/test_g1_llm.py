"""pytest suite for the G1 cross-skill detector LLM dispatch path (Task 4b).

Covers the additions on top of Task 4a:
    * llm_dispatch DI hook + structured record
    * anti-hallucination evidence validator (line range + substring)
    * drop counter + >=3-drops-raises contract (RuntimeError)
    * graceful handling of missing/malformed dispatch replies
    * stderr fallback warning when no dispatch supplied
    * prompt template file is readable

All LLM dispatches are mocked — no real API call.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_SCRIPTS = Path(__file__).resolve().parents[1]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from detectors import g1_cross_skill_dup as g1  # noqa: E402


def _long_para(label: str, lines: int = 6, words_per_line: int = 8) -> str:
    body = " ".join(f"{label}word{i}" for i in range(words_per_line))
    return "\n".join(f"{body} L{i}" for i in range(lines))


def _write(tmp: Path, name: str, *paragraphs: str) -> str:
    p = tmp / name
    p.write_text("\n\n".join(paragraphs) + "\n", encoding="utf-8")
    return str(p)


def _mk_dispatch(
    *,
    is_paraphrased: bool = True,
    evidence_a_override: str | None = None,
    quote_a: str | None = None,
    confidence: str = "medium",
    return_value: object | None = None,
):
    """Mock dispatch with configurable hallucination modes."""
    def _dispatch(record: dict) -> object:
        if return_value is not None:
            return return_value
        pa, pb = record["paragraph_a"], record["paragraph_b"]
        out = {
            "is_paraphrased": is_paraphrased,
            "confidence": confidence,
            "evidence_a": evidence_a_override or pa["lines"],
            "evidence_b": pb["lines"],
            "reasoning": "mock",
        }
        if quote_a is not None:
            out["evidence_quote_a"] = quote_a
        return out
    return _dispatch


# ---- DI happy path ----------------------------------------------------------

def test_dispatch_paraphrased_emits_finding(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("shared", lines=10))
    b = _write(tmp_path, "b.md", _long_para("shared", lines=10))
    findings = g1.detect([a, b], llm_dispatch=_mk_dispatch(confidence="high"))
    assert len(findings) == 1
    f = findings[0]
    assert f["axis"] == "G1" and f["severity"] == "MED"
    assert f["confidence"] == "medium"  # detector confidence_for(2 skills)
    assert len({loc["file"] for loc in f["locations"]}) == 2


def test_dispatch_negative_emits_nothing(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    assert g1.detect([a, b], llm_dispatch=_mk_dispatch(is_paraphrased=False)) == []


def test_dispatch_three_skills_is_high(tmp_path):
    paths = [_write(tmp_path, f"{n}.md", _long_para("x")) for n in "abc"]
    findings = g1.detect(paths, llm_dispatch=_mk_dispatch())
    assert len(findings) == 1
    assert findings[0]["severity"] == "HIGH"
    assert findings[0]["confidence"] == "high"


def test_dispatch_receives_structured_record(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    seen: list[dict] = []
    def _spy(record):
        seen.append(record)
        return {"is_paraphrased": False, "confidence": "low",
                "evidence_a": record["paragraph_a"]["lines"],
                "evidence_b": record["paragraph_b"]["lines"]}
    g1.detect([a, b], llm_dispatch=_spy)
    assert len(seen) == 1
    rec = seen[0]
    for side in ("paragraph_a", "paragraph_b"):
        assert {"file", "lines", "text"}.issubset(rec[side])
        assert rec[side]["lines"].startswith("L") and "-L" in rec[side]["lines"]


# ---- anti-hallucination -----------------------------------------------------

def test_out_of_bounds_evidence_drops_and_warns(tmp_path, capsys):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    findings = g1.detect(
        [a, b], llm_dispatch=_mk_dispatch(evidence_a_override="L9000-L9100"),
    )
    assert findings == []
    assert "out-of-bounds" in capsys.readouterr().err


def test_bad_substring_drops(tmp_path, capsys):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    findings = g1.detect(
        [a, b], llm_dispatch=_mk_dispatch(quote_a="not in paragraph xyzzy"),
    )
    assert findings == []
    assert "not a substring" in capsys.readouterr().err


def test_three_drops_raises(tmp_path):
    # 4 files w/ shared paragraph => 6 cross-file pairs > 3 drop limit.
    paths = [_write(tmp_path, f"{n}.md", _long_para("x")) for n in "abcd"]
    with pytest.raises(RuntimeError, match="evidence_quote out-of-bounds"):
        g1.detect(paths,
                  llm_dispatch=_mk_dispatch(evidence_a_override="L9000-L9100"))


def test_malformed_evidence_field_drops(tmp_path, capsys):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    findings = g1.detect(
        [a, b], llm_dispatch=_mk_dispatch(evidence_a_override="not-a-range"),
    )
    assert findings == []
    assert "malformed evidence_a" in capsys.readouterr().err


def test_non_dict_reply_treated_negative(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    findings = g1.detect(
        [a, b], llm_dispatch=_mk_dispatch(return_value="garbage string"),
    )
    assert findings == []


def test_dispatch_missing_fields_dropped(tmp_path, capsys):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    findings = g1.detect(
        [a, b],
        llm_dispatch=_mk_dispatch(return_value={"is_paraphrased": True,
                                                 "confidence": "low",
                                                 "evidence_a": "L1-L6"}),
    )
    assert findings == []
    assert "malformed evidence_b" in capsys.readouterr().err


# ---- fallback paths ---------------------------------------------------------

def test_missing_dispatch_emits_stderr_warning(tmp_path, capsys):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    findings = g1.detect([a, b])  # llm_dispatch=None, no_llm=False
    assert findings == []
    err = capsys.readouterr().err
    assert "no llm_dispatch provided" in err and "metrics-only" in err


def test_no_llm_true_returns_na_advisory(tmp_path):
    """--no-llm ignores llm_dispatch and returns an explicit N/A advisory.

    Old contract: bare [].
    New contract (§6 case-3 fail-loud): returns a list with one N/A advisory;
    no real findings (llm_dispatch must not be called)."""
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    result = g1.detect([a, b], no_llm=True, llm_dispatch=_mk_dispatch())
    real = [f for f in result if not f.get("not_applicable")]
    assert real == [], f"no real findings in --no-llm mode, got: {real}"
    na = [f for f in result if f.get("not_applicable")]
    assert na, "must return at least one N/A advisory in --no-llm mode"


def test_dispatch_raising_caught(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    def _boom(record):
        raise RuntimeError("simulated llm timeout")
    assert g1.detect([a, b], llm_dispatch=_boom) == []


# ---- prompt template --------------------------------------------------------

def test_prompt_template_readable():
    """CONTEXT.md test plan #9."""
    prompt = (Path(__file__).resolve().parents[2]
              / "references" / "llm-prompts" / "g1-prompt.md")
    assert prompt.exists(), prompt
    body = prompt.read_text(encoding="utf-8")
    for needle in ("Output schema", "evidence_a", "is_paraphrased",
                   "Hallucination guards"):
        assert needle in body, needle


def test_validate_evidence_contract(tmp_path):
    a = _write(tmp_path, "a.md", _long_para("x"))
    b = _write(tmp_path, "b.md", _long_para("x"))
    pa = [p for p in g1._parse_paragraphs(a) if p.is_candidate][0]
    pb = [p for p in g1._parse_paragraphs(b) if p.is_candidate][0]
    totals = {a: 99, b: 99}
    ok, reason = g1._validate_evidence(
        {"evidence_a": "L9000-L9100", "evidence_b": pb.lines_field},
        pa, pb, totals)
    assert not ok and "out-of-bounds" in reason
    ok, reason = g1._validate_evidence(
        {"evidence_a": "bad", "evidence_b": pb.lines_field}, pa, pb, totals)
    assert not ok and "malformed" in reason
    ok, reason = g1._validate_evidence(
        {"evidence_a": pa.lines_field, "evidence_b": pb.lines_field,
         "evidence_quote_a": "xyzzy not present"}, pa, pb, totals)
    assert not ok and "not a substring" in reason
    ok, _ = g1._validate_evidence(
        {"evidence_a": pa.lines_field, "evidence_b": pb.lines_field},
        pa, pb, totals)
    assert ok
