"""G1 file-agnostic extension tests (PR-X).

Tests for:
  - Jaccard prefilter: pairs below MIN_PAIR_JACCARD are never dispatched.
  - file-agnostic detection: same-file paraphrased pair emits a finding.
  - disposition logic: divergent-hazard / merge / missing → hazard.
  - cross-skill regression: two-file paraphrased pair still emits, no disposition.
  - single-path: >= 2 candidates succeeds; < 2 candidates raises.

All LLM calls stubbed. Tests observe the emitted findings schema only —
they do NOT assert on detector internals beyond what is observable through
the public API (detect()) and finding fields.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_SCRIPTS = Path(__file__).resolve().parents[1]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from detectors import g1_cross_skill_dup as g1  # noqa: E402


# ---- helpers -----------------------------------------------------------------

def _long_para(label: str, lines: int = 6, words_per_line: int = 8) -> str:
    """Build a >= 30-word paragraph. Same label → Jaccard = 1.0 (passes filter)."""
    body = " ".join(f"{label}word{i}" for i in range(words_per_line))
    return "\n".join(f"{body} L{i}" for i in range(lines))


def _disjoint_para(label: str, lines: int = 6, words_per_line: int = 8) -> str:
    """Build a paragraph whose token set is unique to ``label`` (zero shared
    tokens with any other label's paragraph). Uses a hash-based label prefix
    so line-index tokens are also label-specific (no shared q0/q1/... tokens).
    """
    h = abs(hash(label)) % 100000  # stable positive int per label
    body = " ".join(f"uniq{h}w{i}" for i in range(words_per_line))
    return "\n".join(f"{body} r{h}l{i}" for i in range(lines))


def _write(tmp: Path, name: str, *paragraphs: str) -> str:
    p = tmp / name
    p.write_text("\n\n".join(paragraphs) + "\n", encoding="utf-8")
    return str(p)


PARAPHRASED_MERGE = {
    "is_paraphrased": True,
    "confidence": "medium",
    "carries_divergent_value": False,
}
PARAPHRASED_HAZARD = {
    "is_paraphrased": True,
    "confidence": "medium",
    "carries_divergent_value": True,
}
PARAPHRASED_NO_CDV = {
    "is_paraphrased": True,
    "confidence": "medium",
    # carries_divergent_value absent — conservative default → hazard
}
NOT_PARAPHRASED = {"is_paraphrased": False, "confidence": "low"}


# ---- Jaccard prefilter -------------------------------------------------------

def test_jaccard_below_threshold_never_dispatches(tmp_path):
    """A pair with Jaccard < MIN_PAIR_JACCARD must never reach the dispatch callable.

    Uses two files whose paragraphs have fully disjoint vocabulary so
    Jaccard = 0.0. The dispatch spy must NOT be called.
    """
    a = _write(tmp_path, "a.md", _disjoint_para("alpha"))
    b = _write(tmp_path, "b.md", _disjoint_para("beta"))

    dispatch_calls: list = []

    def spy_dispatch(record: dict) -> dict:
        dispatch_calls.append(record)
        return PARAPHRASED_MERGE

    # Both files have 1 candidate each → 2 candidates total → no ValueError.
    # The pair's Jaccard is 0.0 → prefilter must block it.
    findings = g1.detect([a, b], llm_dispatch=spy_dispatch)

    assert dispatch_calls == [], (
        f"dispatch was called {len(dispatch_calls)} time(s) but the pair "
        f"is below the Jaccard threshold — prefilter failed"
    )
    assert findings == []


def test_jaccard_above_threshold_does_dispatch(tmp_path):
    """A pair with Jaccard >= MIN_PAIR_JACCARD must reach the dispatch callable.

    Same label in both files → Jaccard = 1.0.
    """
    a = _write(tmp_path, "a.md", _long_para("shared"))
    b = _write(tmp_path, "b.md", _long_para("shared"))

    dispatch_calls: list = []

    def spy_dispatch(record: dict) -> dict:
        dispatch_calls.append(record)
        # Return a valid evidence shape so the finding is emitted cleanly.
        pa = record["paragraph_a"]
        pb = record["paragraph_b"]
        return {
            "is_paraphrased": True,
            "confidence": "medium",
            "carries_divergent_value": False,
            "evidence_a": pa["lines"],
            "evidence_b": pb["lines"],
        }

    g1.detect([a, b], llm_dispatch=spy_dispatch)

    assert len(dispatch_calls) == 1, (
        f"dispatch should be called once for the single candidate pair; "
        f"got {len(dispatch_calls)}"
    )


# ---- file-agnostic: intra-file finding ---------------------------------------

def test_same_file_paraphrase_emits_finding(tmp_path):
    """Two same-file paragraphs judged is_paraphrased=True must emit a finding.

    Previously suppressed by the 'if a.file == b.file: continue' guard
    (L310 before PR-X). After PR-X that guard is lifted.
    """
    # Two paragraphs with the same label → Jaccard = 1.0.
    f = _write(tmp_path, "single.md", _long_para("rule"), _long_para("rule"))

    def dispatch(record: dict) -> dict:
        pa = record["paragraph_a"]
        pb = record["paragraph_b"]
        return {
            "is_paraphrased": True,
            "confidence": "medium",
            "carries_divergent_value": False,
            "evidence_a": pa["lines"],
            "evidence_b": pb["lines"],
        }

    findings = g1.detect([f], llm_dispatch=dispatch)

    assert len(findings) == 1, (
        "expected 1 intra-file finding; "
        f"got {len(findings)} (same-file skip still active?)"
    )
    locs = findings[0]["locations"]
    files = {loc["file"] for loc in locs}
    assert files == {f}, "all locations must point to the single input file"


# ---- disposition logic -------------------------------------------------------

def test_intra_file_divergent_value_true_gives_divergent_hazard(tmp_path):
    """carries_divergent_value=True → disposition='divergent-hazard'."""
    f = _write(tmp_path, "s.md", _long_para("rule"), _long_para("rule"))

    def dispatch(record: dict) -> dict:
        pa, pb = record["paragraph_a"], record["paragraph_b"]
        return {
            "is_paraphrased": True, "confidence": "medium",
            "carries_divergent_value": True,
            "evidence_a": pa["lines"], "evidence_b": pb["lines"],
        }

    findings = g1.detect([f], llm_dispatch=dispatch)
    assert len(findings) == 1
    assert findings[0]["disposition"] == "divergent-hazard"


def test_intra_file_divergent_value_false_gives_merge(tmp_path):
    """carries_divergent_value=False → disposition='merge'."""
    f = _write(tmp_path, "s.md", _long_para("rule"), _long_para("rule"))

    def dispatch(record: dict) -> dict:
        pa, pb = record["paragraph_a"], record["paragraph_b"]
        return {
            "is_paraphrased": True, "confidence": "medium",
            "carries_divergent_value": False,
            "evidence_a": pa["lines"], "evidence_b": pb["lines"],
        }

    findings = g1.detect([f], llm_dispatch=dispatch)
    assert len(findings) == 1
    assert findings[0]["disposition"] == "merge"


def test_intra_file_missing_cdv_gives_divergent_hazard(tmp_path):
    """Missing carries_divergent_value (uncertain) → default-conservative 'divergent-hazard'."""
    f = _write(tmp_path, "s.md", _long_para("rule"), _long_para("rule"))

    def dispatch(record: dict) -> dict:
        pa, pb = record["paragraph_a"], record["paragraph_b"]
        # No carries_divergent_value key.
        return {
            "is_paraphrased": True, "confidence": "medium",
            "evidence_a": pa["lines"], "evidence_b": pb["lines"],
        }

    findings = g1.detect([f], llm_dispatch=dispatch)
    assert len(findings) == 1
    assert findings[0]["disposition"] == "divergent-hazard"


# ---- cross-skill regression --------------------------------------------------

def test_cross_skill_finding_has_no_disposition(tmp_path):
    """Cross-file (different files) paraphrased pair emits a finding with no
    'disposition' field (absent) — existing extract-to-_shared prescription
    unchanged.
    """
    a = _write(tmp_path, "a.md", _long_para("shared"))
    b = _write(tmp_path, "b.md", _long_para("shared"))

    def dispatch(record: dict) -> dict:
        pa, pb = record["paragraph_a"], record["paragraph_b"]
        return {
            "is_paraphrased": True, "confidence": "medium",
            "carries_divergent_value": False,
            "evidence_a": pa["lines"], "evidence_b": pb["lines"],
        }

    findings = g1.detect([a, b], llm_dispatch=dispatch)
    assert len(findings) == 1

    # No disposition field for cross-file findings.
    assert "disposition" not in findings[0], (
        "cross-file finding must NOT carry a 'disposition' field; "
        "only intra-file findings get disposition"
    )

    # Must span two files (cross-skill contract unchanged).
    loc_files = {loc["file"] for loc in findings[0]["locations"]}
    assert len(loc_files) == 2


def test_cross_skill_existing_fields_unchanged(tmp_path):
    """Cross-file finding still has the standard G1 required fields."""
    a = _write(tmp_path, "a.md", _long_para("shared"))
    b = _write(tmp_path, "b.md", _long_para("shared"))

    def dispatch(record: dict) -> dict:
        pa, pb = record["paragraph_a"], record["paragraph_b"]
        return {
            "is_paraphrased": True, "confidence": "medium",
            "evidence_a": pa["lines"], "evidence_b": pb["lines"],
        }

    findings = g1.detect([a, b], llm_dispatch=dispatch)
    assert findings
    f = findings[0]
    for field in ("id", "axis", "severity", "confidence", "locations",
                  "evidence_quote", "suggested_action", "requires_human",
                  "numeric_basis"):
        assert field in f, f"required field {field!r} missing from cross-file finding"
    assert f["axis"] == "G1"
    assert f["requires_human"] is True
    assert f["numeric_basis"] is None


# ---- single-path contract ----------------------------------------------------

def test_single_path_two_candidates_no_raise(tmp_path):
    """Single file with >= 2 candidate paragraphs must NOT raise (self-compare)."""
    f = _write(tmp_path, "single.md", _long_para("a"), _long_para("b"))
    # Should not raise; may return [] if Jaccard filters the pair (a vs b = 0.27).
    # The contract is no ValueError — result can be empty.
    try:
        result = g1.detect([f], no_llm=True)
    except ValueError as exc:
        pytest.fail(f"detect() raised ValueError on single file with 2 candidates: {exc}")
    assert isinstance(result, list)


def test_single_path_one_candidate_raises(tmp_path):
    """Single file with only 1 candidate paragraph must raise ValueError."""
    f = _write(tmp_path, "single.md", _long_para("only"))
    with pytest.raises(ValueError, match="needs >= 2 candidate paragraphs"):
        g1.detect([f])


def test_single_path_with_two_same_label_candidates_can_find(tmp_path):
    """Single file, 2 same-label candidates (Jaccard=1.0), dispatch returns
    paraphrased → a finding IS emitted (end-to-end single-path success path).
    """
    f = _write(tmp_path, "single.md", _long_para("rule"), _long_para("rule"))

    def dispatch(record: dict) -> dict:
        pa, pb = record["paragraph_a"], record["paragraph_b"]
        return {
            "is_paraphrased": True, "confidence": "medium",
            "carries_divergent_value": False,
            "evidence_a": pa["lines"], "evidence_b": pb["lines"],
        }

    findings = g1.detect([f], llm_dispatch=dispatch)
    assert len(findings) == 1
    assert findings[0]["axis"] == "G1"
