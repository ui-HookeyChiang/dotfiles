"""Pytest cases for task-2 ``merge-findings.py`` (G4 ordering/merge + G7
sentence-level meta precedence).

Each test invokes ``merge-findings.py`` against a fixture YAML under
``fixtures/merge/`` and asserts the expected exit code + stdout shape. Expected
exits/streams are derived from the spec ``Testing`` table (docs/specs/active/
2026-06-02-prose-guidelines-reliability-hardening.md), not from the implementation.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SKILL_ROOT = REPO_ROOT / "prose-guidelines"
MERGE = SKILL_ROOT / "scripts" / "merge-findings.py"
FIXTURES = SKILL_ROOT / "scripts" / "tests" / "fixtures" / "merge"


def _run(yaml_name: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["python3", str(MERGE), str(FIXTURES / yaml_name)],
        capture_output=True,
        text=True,
        check=False,
    )


# --- G4/G7 same-range merge with sentence-level meta precedence ----------


def test_merge_same_range_meta_wins() -> None:
    """A meta + a lexical finding on the SAME range collapse to ONE apply unit;
    the meta sentence is deleted and the lexical change applies to the
    fact-bearing remainder (which Gate 7 already confirmed keeps 3/Prometheus)."""
    res = _run("merge-same-range-meta-wins.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    assert len(out["units"]) == 1, out
    unit = out["units"][0]
    # meta sentence removed
    assert "This section describes the pipeline." not in unit["new_string"], unit
    # fact-bearing remainder survives + lexical applied to it (reporting dropped)
    assert "3 stages to Prometheus" in unit["new_string"], unit
    assert "reporting" not in unit["new_string"], unit
    # both source classes folded into the one unit
    assert "meta" in unit["sources"] and "lexical" in unit["sources"], unit


# --- G4 overlapping-but-distinct ranges rejected -------------------------


def test_merge_overlap_distinct_fail() -> None:
    """Two DIFFERENT source ranges that overlap (share a line) are a conflict;
    the script exits non-zero rather than silently clobbering."""
    res = _run("merge-overlap-distinct-fail.yaml")
    assert res.returncode != 0, f"expected non-zero, got 0; stdout={res.stdout!r}"


# --- G4(a) bottom-up apply order (start-line DESCENDING) -----------------


def test_merge_units_sorted_start_line_descending() -> None:
    """Accepted findings emit as apply units ordered by start-line DESC so an
    earlier Edit never shifts a later finding's line numbers."""
    res = _run("merge-same-range-meta-wins.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    starts = [u["start_line"] for u in out["units"]]
    assert starts == sorted(starts, reverse=True), starts


# --- G4(d) non-unique old_string -> skip (no fuzzy) ----------------------


def test_merge_nonunique_oldstring_skipped() -> None:
    """A finding whose raw range text is NOT unique in the file is skipped
    (reported), never best-effort applied — exit 0, zero units, one skip."""
    res = _run("merge-nonunique-oldstring-skip.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    assert out["units"] == [], out
    assert len(out["skipped"]) == 1, out
    assert "not unique" in out["skipped"][0]["reason"], out


# --- whole-span replace: partial evidence must not leak the uncited remainder --

_COMPRESSED = "The service caches reads to cut latency and retries failed writes up to 3 times."
_UNCITED_2ND = "It also retries failed writes up to 3 times."


def test_merge_partial_evidence_whole_span() -> None:
    """A non-meta finding whose evidence_quote covers only the FIRST sentence of
    a 2-sentence paragraph but whose rewritten_text compresses the WHOLE
    paragraph must replace the entire span — the uncited 2nd original sentence
    must NOT survive appended alongside the compressed sentence."""
    res = _run("merge-partial-evidence-whole-span.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    assert len(out["units"]) == 1, out
    unit = out["units"][0]
    # whole span replaced with exactly the compressed rewritten_text
    assert unit["new_string"].strip() == _COMPRESSED, unit
    # no leftover fragment from the uncited 2nd original sentence
    assert _UNCITED_2ND not in unit["new_string"], unit


def test_merge_full_coverage_whole_span() -> None:
    """When evidence_quote covers the WHOLE paragraph, whole-span replace is a
    no-op against the non-bug case: new_string is exactly rewritten_text."""
    res = _run("merge-full-coverage-whole-span.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    assert len(out["units"]) == 1, out
    assert out["units"][0]["new_string"].strip() == _COMPRESSED, out


def test_merge_empty_rewrite_whole_span() -> None:
    """Empty rewritten_text on a non-meta finding collapses the surviving span
    to an empty string (pure deletion)."""
    res = _run("merge-empty-rewrite-whole-span.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    assert len(out["units"]) == 1, out
    assert out["units"][0]["new_string"] == "", out


def test_merge_two_nonmeta_conflict_skipped() -> None:
    """Two non-meta findings on one span is an ambiguous compose — the unit is
    pushed to skipped[] with a conflict reason, never silently merged."""
    res = _run("merge-two-nonmeta-conflict.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    assert out["units"] == [], out
    assert len(out["skipped"]) == 1, out
    assert "non-meta" in out["skipped"][0]["reason"], out


# --- meta + single non-meta whole-span contract -------------------------------

_META_SENT = "This section describes the pipeline."
_FACT_SENT = "The flow has 3 stages reporting to Prometheus."


def test_merge_meta_plus_nonmeta_whole_span() -> None:
    """A meta + a SINGLE non-meta finding on one span: the meta deletes its own
    sentence, the non-meta whole-span rewrite applies to the remainder. Even
    when the non-meta rewrite echoes the meta sentence, meta precedence drops
    it; the fact-bearing remainder survives."""
    res = _run("merge-meta-plus-nonmeta-whole-span.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    assert len(out["units"]) == 1, out
    unit = out["units"][0]
    # meta-deleted sentence dropped even though the non-meta rewrite re-echoed it
    assert _META_SENT not in unit["new_string"], unit
    # fact-bearing remainder (with the lexical compression applied) survives
    assert "The flow has 3 stages to Prometheus." in unit["new_string"], unit
    assert "meta" in unit["sources"] and "paragraph" in unit["sources"], unit


def test_merge_meta_subtraction_content_loss_guard() -> None:
    """CASE-A edge: the single non-meta rewrite contains ONLY the meta-deleted
    sentence, so subtracting meta_deleted empties ``kept``. The span must NOT
    silently collapse to "" — it falls back to the surviving (meta-kept)
    sentences rather than annihilating content the meta intended to preserve."""
    res = _run("merge-meta-subtraction-content-loss.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    out = json.loads(res.stdout)
    assert len(out["units"]) == 1, out
    unit = out["units"][0]
    # the span did NOT collapse to empty
    assert unit["new_string"].strip() != "", unit
    # meta precedence: its own sentence stays deleted
    assert _META_SENT not in unit["new_string"], unit
    # surviving fact-bearing sentence is preserved, not annihilated
    assert _FACT_SENT in unit["new_string"], unit
