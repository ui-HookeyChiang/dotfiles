"""Unit tests for G8 progressive disclosure detector.

Test plan covers (mock LLM only):
  1. py_compile sanity (test collection alone exercises import).
  2. rule layer: code block / rationale heading / bullet enumeration.
  3. four fusion rules.
  4. severity boundary at 10 / 20 / 30 movable lines.
  5. evidence_quote out-of-bounds drop + counter.
  6. >= 3 out-of-bounds drops -> SystemExit(1).
  7. no_llm=True mode: rule-only, rule-3 cannot fire.
  8. dogfood: flow-dev/SKILL.md mock LLM run -> >= 1 finding.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_SCRIPT_DIR = Path(__file__).resolve().parent.parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from detectors import g8_progressive_disclosure as g8  # noqa: E402

def test_code_block_under_threshold_skipped(tmp_path: Path) -> None:
    body = "\n".join(["```python", *["x = 1"] * 10, "```"])
    segs = g8._scan_code_blocks(body.splitlines())
    assert segs == []

def test_code_block_at_threshold_detected(tmp_path: Path) -> None:
    body = "\n".join(["```python", *["x = 1"] * 18, "```"])  # 20 lines total
    segs = g8._scan_code_blocks(body.splitlines())
    assert len(segs) == 1 and segs[0].kind == "code_block"
    assert segs[0].movable_lines == 20

def test_rationale_heading_extends_to_next_same_depth(tmp_path: Path) -> None:
    body = "\n".join([
        "# Title",
        "## Why this thing exists",
        "Because reasons.",
        "More reasons.",
        "## Next heading",
        "Other content.",
    ])
    segs = g8._scan_rationale_headings(body.splitlines())
    assert len(segs) == 1
    assert segs[0].start == 2 and segs[0].end == 4

def test_bullet_enumeration_detects_five_in_a_row() -> None:
    body = "\n".join(["- a", "- b", "- c", "- d", "- e"])
    segs = g8._scan_bullet_enumeration(body.splitlines())
    assert len(segs) == 1 and segs[0].movable_lines == 5

def test_bullet_enumeration_under_threshold_skipped() -> None:
    body = "\n".join(["- a", "- b", "- c", "- d"])
    assert g8._scan_bullet_enumeration(body.splitlines()) == []

def test_fusion_rule_1_rule_hit_actionable_drop() -> None:
    action, reason = g8._fuse(rule_hit=True, llm_class="actionable", movable_lines=50)
    assert action == "drop"
    assert reason == "rule_overruled_by_llm_actionable"

def test_fusion_rule_2_rule_hit_reference_report_high() -> None:
    action, conf = g8._fuse(rule_hit=True, llm_class="reference", movable_lines=25)
    assert action == "report"
    assert conf == "high"

def test_fusion_rule_3_llm_only_report_medium() -> None:
    action, conf = g8._fuse(rule_hit=False, llm_class="rationale", movable_lines=30)
    assert action == "report"
    assert conf == "medium"

def test_fusion_rule_4_below_low_threshold_drop() -> None:
    action, reason = g8._fuse(rule_hit=True, llm_class="reference", movable_lines=9)
    assert action == "drop"
    assert reason == "below_low_threshold"

@pytest.mark.parametrize("lines, expected", [
    (9, None), (10, "LOW"), (19, "LOW"),
    (20, "MED"), (29, "MED"),
    (30, "HIGH"), (100, "HIGH"),
])
def test_severity_boundaries(lines: int, expected: str | None) -> None:
    assert g8._severity(lines) == expected

def test_evidence_out_of_bounds_dropped_and_counted() -> None:
    counter = g8._OutOfBoundsCounter()
    finding = {
        "locations": [{"file": "x.md", "lines": "L1-L999"}],
    }
    assert g8._validate_evidence(finding, ["a", "b"], counter) is False
    assert counter.count == 1

def test_evidence_in_bounds_passes() -> None:
    counter = g8._OutOfBoundsCounter()
    finding = {
        "locations": [{"file": "x.md", "lines": "L1-L2"}],
    }
    assert g8._validate_evidence(finding, ["a", "b"], counter) is True
    assert counter.count == 0

def test_three_out_of_bounds_raises_systemexit() -> None:
    counter = g8._OutOfBoundsCounter()
    bad = {"locations": [{"file": "x.md", "lines": "L9-L99"}]}
    g8._validate_evidence(bad, ["a"], counter)
    g8._validate_evidence(bad, ["a"], counter)
    with pytest.raises(SystemExit):
        g8._validate_evidence(bad, ["a"], counter)

def _make_skill(tmp_path: Path, body: str) -> Path:
    p = tmp_path / "SKILL.md"
    p.write_text(body, encoding="utf-8")
    return p

def _mock_llm_reference(seg: g8.Segment, lines: list[str]) -> dict:
    """LLM always classifies as reference."""
    return {
        "classification": "reference",
        "confidence": "high",
        "suggested_move_target": "REFERENCE.md",
        "evidence_quote": f"L{seg.start}-L{seg.end}: {seg.snippet}",
    }

def _mock_llm_actionable(seg: g8.Segment, lines: list[str]) -> dict:
    return {"classification": "actionable", "confidence": "high",
            "suggested_move_target": "stay", "evidence_quote": ""}

def test_detect_no_llm_mode_rule_only(tmp_path: Path) -> None:
    body = "\n".join(["# H", "```python", *["x = 1"] * 28, "```"])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], no_llm=True)
    assert len(findings) == 1
    f = findings[0]
    assert f["axis"] == "G8"
    assert f["severity"] == "HIGH"      # 30-line block
    assert f["confidence"] == "high"
    assert f["numeric_basis"] is None
    assert f["requires_human"] is True

def test_detect_mock_reference_emits_finding(tmp_path: Path) -> None:
    body = "\n".join(["# H", "```python", *["x = 1"] * 28, "```"])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], llm_fn=_mock_llm_reference)
    assert len(findings) == 1
    assert findings[0]["confidence"] == "high"     # fusion rule 2

def test_detect_mock_actionable_drops_finding(tmp_path: Path) -> None:
    body = "\n".join(["# H", "```python", *["x = 1"] * 28, "```"])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], llm_fn=_mock_llm_actionable)
    assert findings == []                          # fusion rule 1

def test_detect_below_low_threshold_dropped(tmp_path: Path) -> None:
    # only 5 bullets, movable=5 < LOW threshold (10)
    body = "\n".join(["# H", "- a", "- b", "- c", "- d", "- e"])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], llm_fn=_mock_llm_reference)
    assert findings == []                          # fusion rule 4

def test_detect_default_llm_raises_without_no_llm(tmp_path: Path) -> None:
    body = "\n".join(["```python", *["x = 1"] * 28, "```"])
    p = _make_skill(tmp_path, body)
    with pytest.raises(NotImplementedError):
        g8.detect([str(p)])  # no llm_fn, no no_llm -> default dispatch raises

def _mock_llm_lying(seg: g8.Segment, lines: list[str]) -> dict:
    # claims an out-of-bounds quote — detector should drop the finding
    return {
        "classification": "reference", "confidence": "high",
        "suggested_move_target": "REFERENCE.md",
        "evidence_quote": "fake quote",
    }

def test_three_consecutive_oob_raises_systemexit(tmp_path: Path) -> None:
    # Three code blocks all matched, mock LLM dispatch returns reference,
    # but a separate evidence_quote with bogus line range. We trigger it by
    # building findings directly.
    counter = g8._OutOfBoundsCounter()
    bad = {"locations": [{"file": "x.md", "lines": "L99-L100"}]}
    g8._validate_evidence(bad, ["only one line"], counter)
    g8._validate_evidence(bad, ["only one line"], counter)
    with pytest.raises(SystemExit):
        g8._validate_evidence(bad, ["only one line"], counter)

def test_dogfood_stacking_dev_skillmd_emits_findings() -> None:
    repo_root = Path(__file__).resolve().parents[3]
    target = repo_root / "flow-dev" / "SKILL.md"
    if not target.exists():
        pytest.skip("flow-dev/SKILL.md not present in this worktree")
    findings = g8.detect([str(target)], llm_fn=_mock_llm_reference)
    assert len(findings) >= 1
    for f in findings:
        assert f["axis"] == "G8"
        assert f["severity"] in ("HIGH", "MED", "LOW")
        assert f["locations"][0]["file"] == str(target)
