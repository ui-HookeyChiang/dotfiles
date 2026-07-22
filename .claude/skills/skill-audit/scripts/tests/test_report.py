"""Tests for advisory report renderer."""
import json
from pathlib import Path
from advisory.report import render_markdown, render_json, ReportInput
from advisory.metrics import (
    SizeMetric, ImbalanceMetric, StalenessMetric, NavigabilityMetric,
    CrossSectionHints,
)
from advisory.llm_dispatch import LLMResult, LLMStatus


def make_input(with_llm=False):
    return ReportInput(
        target=Path("/path/to/SKILL.md"),
        mode="metrics-with-llm" if with_llm else "metrics",
        size=SizeMetric(lines_total=587, lines_prose=400, bytes_total=19000,
                        fenced_blocks=24, score=98.0),
        imbalance=ImbalanceMetric(substantive_blocks=24, scripts_count=3,
                                  imbalance_ratio=8.0, score=80.0),
        staleness=StalenessMetric(last_modified_days=12, meaningful_edits_90d=4,
                                  score=7.0),
        navigability=NavigabilityMetric(ordinal_ids=38, mode_notes=6,
                                        line_span=400, score=90.0),
        hints=CrossSectionHints(phrases=[
            {"phrase": "AWS DryRun", "sections": ["Quick Start", "AWS Signing Setup", "Troubleshooting"]},
        ]),
        composite=68.0,
        threshold=30,
        llm_result=LLMResult(status=LLMStatus.NOT_DISPATCHED) if not with_llm else None,
        ranking=None,
    )


def test_markdown_metrics_only():
    md = render_markdown(make_input(with_llm=False))
    assert "advisory report" in md.lower()
    assert "587" in md
    assert "98" in md
    assert "Composite" in md
    assert "AWS DryRun" in md
    # Post-PR0b: LLM-kind H3 subsections are absent when LLM not dispatched.
    for kin in ("### Paraphrased redundancy", "### Semantic scriptifiable",
                "### Contradictions", "### Covered by existing wrapper"):
        assert kin not in md, kin


def test_markdown_includes_llm_findings():
    inp = make_input(with_llm=True)
    inp.llm_result = LLMResult(
        status=LLMStatus.OK,
        findings={
            "paraphrased_redundancy": [{
                "locations": ["62-64", "249-251"],
                "summary": "AWS DryRun in 3 sections",
                "severity": "MED",
                "refactor": "extract scripts/verify-aws-signer.sh",
                "saved_lines": 10,
            }],
            "semantic_scriptifiable": [],
            "contradictions": [],
            "covered_by_wrapper": [],
        },
    )
    md = render_markdown(inp)
    # Post-PR0b: presence asserted via the H3 subsection that survives
    # the gate (`if items: continue` in report.py).
    assert any(h in md for h in (
        "### Paraphrased redundancy",
        "### Semantic scriptifiable",
        "### Contradictions",
        "### Covered by existing wrapper",
    ))
    assert "AWS DryRun in 3 sections" in md
    assert "MED" in md


def test_json_round_trips():
    inp = make_input(with_llm=False)
    out = render_json(inp)
    data = json.loads(out)
    assert data["version"] == 1
    assert data["mode"] == "metrics"
    assert data["metrics"]["size"]["lines_total"] == 587
    assert data["composite"]["score"] == 68.0
    assert data["composite"]["exit_code_preview"] == 0


def test_json_exit_code_preview_low_composite():
    inp = make_input(with_llm=False)
    inp.composite = 25.0
    data = json.loads(render_json(inp))
    assert data["composite"]["exit_code_preview"] == 2


def test_markdown_renders_confirmed_stale_drift_note():
    """A confirmed kind=stale finding renders [stale] + drift_note, and does
    NOT print the loud-empty '0 confirmed' line (it IS confirmed)."""
    inp = make_input(with_llm=True)
    inp.llm_result = LLMResult(
        status=LLMStatus.OK,
        findings={
            "behavior_mismatch": [{
                "locations": ["10-10"],
                "summary": "phantom validate.py",
                "kind": "stale",
                "severity": "HIGH",
                "removal_suggestion": "consider-removing",
                "drift_note": "prose-stale; scripts/validate.py absent",
            }],
        },
    )
    md = render_markdown(inp)
    assert "### Behavior mismatch" in md
    assert "[stale]" in md
    assert "Drift: prose-stale; scripts/validate.py absent" in md
    # A confirmed finding must NOT be mislabelled "0 confirmed".
    assert "candidates seen" not in md


def test_markdown_renders_loud_empty_sentinel():
    """The loud-empty sentinel (kind=stale, removal_suggestion=keep) renders
    the exact 'N candidates seen, 0 confirmed' line, distinguishing a
    judged-clean pass from a detector that produced no candidates."""
    inp = make_input(with_llm=True)
    inp.llm_result = LLMResult(
        status=LLMStatus.OK,
        findings={
            "behavior_mismatch": [{
                "locations": ["1-1"],
                "summary": "stale-drift: no confirmed candidates",
                "kind": "stale",
                "severity": "LOW",
                "removal_suggestion": "keep",
                "drift_note": "3 candidates seen, 0 confirmed",
                "drift_candidates_seen": 3,
            }],
        },
    )
    md = render_markdown(inp)
    assert "[stale]" in md
    assert "3 candidates seen, 0 confirmed" in md
