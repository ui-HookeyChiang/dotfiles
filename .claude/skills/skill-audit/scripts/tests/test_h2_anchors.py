"""State-table-driven tests for unified H2 anchor contract (spec
2026-05-27-syntax-audit-unified-mode).

After PR0b, both advisory (`_run_advisory` → `render_markdown`) and
legacy (`_run_legacy` → `render_report`) codepaths must emit exactly
two top-level H2 anchors per single-target invocation:

  - `## Bloat metrics` (replacing `## Metrics` / `## Summary`)
  - `## Findings` (always emitted; body depends on mode + state)

Per-state body shape is enumerated in the spec's §Design state
table. Each test below names the row it covers in its docstring.

These tests construct `ReportInput` / call `render_report` directly
— no subprocess, no live LLM. LLM-related cases build `LLMResult`
per `llm_dispatch.py:25-30` dataclass shape.
"""
from __future__ import annotations

import re
from pathlib import Path

from advisory.report import render_markdown, ReportInput
from advisory.metrics import (
    SizeMetric,
    ImbalanceMetric,
    StalenessMetric,
    NavigabilityMetric,
    CrossSectionHints,
)
from advisory.llm_dispatch import LLMResult, LLMStatus
from syntax_audit import Finding, render_report


# ---------------------------------------------------------------------------
# Helpers

def _h2_lines(md: str) -> list[str]:
    """Return all `^## …` H2 headings (exactly two leading hashes)."""
    return [ln for ln in md.splitlines() if re.match(r"^## (?!#)", ln)]


def _h3_lines(md: str) -> list[str]:
    return [ln for ln in md.splitlines() if re.match(r"^### (?!#)", ln)]


def _make_advisory_input(
    *,
    hints_phrases: list[dict] | None = None,
    llm_result: LLMResult | None = None,
) -> ReportInput:
    return ReportInput(
        target=Path("/path/to/SKILL.md"),
        mode="metrics-with-llm" if llm_result else "metrics",
        size=SizeMetric(
            lines_total=400, lines_prose=300, bytes_total=12000,
            fenced_blocks=10, score=70.0,
        ),
        imbalance=ImbalanceMetric(
            substantive_blocks=10, scripts_count=2,
            imbalance_ratio=5.0, score=50.0,
        ),
        staleness=StalenessMetric(
            last_modified_days=30, meaningful_edits_90d=2, score=20.0,
        ),
        navigability=NavigabilityMetric(
            ordinal_ids=12, mode_notes=2, line_span=80, score=40.0,
        ),
        hints=CrossSectionHints(phrases=hints_phrases or []),
        composite=50.0,
        threshold=30,
        llm_result=llm_result,
        ranking=None,
    )


def _llm_ok_with_items() -> LLMResult:
    return LLMResult(
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


def _llm_ok_empty() -> LLMResult:
    return LLMResult(
        status=LLMStatus.OK,
        findings={
            "paraphrased_redundancy": [],
            "semantic_scriptifiable": [],
            "contradictions": [],
            "covered_by_wrapper": [],
        },
    )


def _llm_failed(status: LLMStatus = LLMStatus.PARSE_FAIL) -> LLMResult:
    return LLMResult(
        status=status,
        findings={},
        raw_response="not yaml at all",
        error="could not parse YAML response",
    )


def _hint_phrase() -> list[dict]:
    return [{
        "phrase": "AWS DryRun",
        "sections": ["Quick Start", "AWS Signing", "Troubleshooting"],
    }]


# ---------------------------------------------------------------------------
# Advisory mode cases (8 rows)

def test_advisory_hints_plus_llm_ok_with_items():
    """State-table row: advisory | hints + LLM OK with items."""
    inp = _make_advisory_input(
        hints_phrases=_hint_phrase(),
        llm_result=_llm_ok_with_items(),
    )
    md = render_markdown(inp)

    h2s = _h2_lines(md)
    assert "## Bloat metrics" in h2s
    assert "## Findings" in h2s
    assert "## Metrics" not in h2s
    assert "## Cross-section hints (LLM prior, not scored)" not in h2s
    assert "## LLM findings" not in h2s

    # Both subsections present under ## Findings
    h3s = _h3_lines(md)
    assert "### Cross-section hints (LLM prior, not scored)" in h3s
    assert any("### Paraphrased redundancy" in h for h in h3s)


def test_advisory_hints_only_llm_not_dispatched():
    """State-table row: advisory | hints only (LLM not dispatched)."""
    inp = _make_advisory_input(
        hints_phrases=_hint_phrase(),
        llm_result=LLMResult(status=LLMStatus.NOT_DISPATCHED),
    )
    md = render_markdown(inp)

    h2s = _h2_lines(md)
    assert "## Bloat metrics" in h2s
    assert "## Findings" in h2s

    h3s = _h3_lines(md)
    assert "### Cross-section hints (LLM prior, not scored)" in h3s
    # No LLM-kind headings
    for kin in ("### Paraphrased redundancy", "### Semantic scriptifiable",
                "### Contradictions", "### Covered by existing wrapper",
                "### LLM dispatch failed"):
        assert not any(h.startswith(kin) for h in h3s), kin


def test_advisory_llm_ok_items_only_no_hints():
    """State-table row: advisory | LLM OK with items only (no hints)."""
    inp = _make_advisory_input(
        hints_phrases=[],
        llm_result=_llm_ok_with_items(),
    )
    md = render_markdown(inp)

    h2s = _h2_lines(md)
    assert "## Bloat metrics" in h2s
    assert "## Findings" in h2s

    h3s = _h3_lines(md)
    assert "### Cross-section hints (LLM prior, not scored)" not in h3s
    assert any(h.startswith("### Paraphrased redundancy") for h in h3s)


def test_advisory_llm_ok_empty_with_hints():
    """State-table row: advisory | LLM OK but empty + hints present.

    LLM section must be gated out (V4 fix) — body has cross-section
    hints subsection only.
    """
    inp = _make_advisory_input(
        hints_phrases=_hint_phrase(),
        llm_result=_llm_ok_empty(),
    )
    md = render_markdown(inp)

    h2s = _h2_lines(md)
    assert "## Findings" in h2s
    assert "## LLM findings" not in h2s

    h3s = _h3_lines(md)
    assert "### Cross-section hints (LLM prior, not scored)" in h3s
    for kin in ("### Paraphrased redundancy", "### Semantic scriptifiable",
                "### Contradictions", "### Covered by existing wrapper",
                "### LLM dispatch failed"):
        assert not any(h.startswith(kin) for h in h3s), kin


def test_advisory_llm_ok_empty_no_hints():
    """State-table row: advisory | LLM OK but empty + no hints.

    Body is the literal degenerate blockquote naming LLM dispatched
    but returned no findings (V4 case missing from V3).
    """
    inp = _make_advisory_input(
        hints_phrases=[],
        llm_result=_llm_ok_empty(),
    )
    md = render_markdown(inp)

    h2s = _h2_lines(md)
    assert "## Findings" in h2s
    assert "## LLM findings" not in h2s

    assert "> No findings detected (LLM dispatched but returned no findings)." in md


def test_advisory_hints_plus_llm_failed():
    """State-table row: advisory | hints + LLM failed.

    Body has `### Cross-section hints` first, then
    `### LLM dispatch failed (<status>)` subsection.
    """
    inp = _make_advisory_input(
        hints_phrases=_hint_phrase(),
        llm_result=_llm_failed(LLMStatus.PARSE_FAIL),
    )
    md = render_markdown(inp)

    h2s = _h2_lines(md)
    assert "## Findings" in h2s
    assert not any(h.startswith("## LLM dispatch failed") for h in h2s)

    h3s = _h3_lines(md)
    assert "### Cross-section hints (LLM prior, not scored)" in h3s
    assert any(h.startswith("### LLM dispatch failed") for h in h3s)

    # Ordering: cross-section before LLM failed
    cs_idx = next(i for i, ln in enumerate(md.splitlines())
                  if ln.startswith("### Cross-section hints"))
    llm_idx = next(i for i, ln in enumerate(md.splitlines())
                   if ln.startswith("### LLM dispatch failed"))
    assert cs_idx < llm_idx


def test_advisory_llm_failed_no_hints():
    """State-table row: advisory | LLM failed, no hints."""
    inp = _make_advisory_input(
        hints_phrases=[],
        llm_result=_llm_failed(LLMStatus.SPAWN_FAIL),
    )
    md = render_markdown(inp)

    h2s = _h2_lines(md)
    assert "## Findings" in h2s
    assert not any(h.startswith("## LLM dispatch failed") for h in h2s)

    h3s = _h3_lines(md)
    assert "### Cross-section hints (LLM prior, not scored)" not in h3s
    assert any(h.startswith("### LLM dispatch failed") for h in h3s)


def test_advisory_degenerate_no_hints_llm_not_dispatched():
    """State-table row: advisory | LLM not dispatched, no hints.

    Body is the literal degenerate blockquote naming both nothing
    happened.
    """
    inp = _make_advisory_input(
        hints_phrases=[],
        llm_result=LLMResult(status=LLMStatus.NOT_DISPATCHED),
    )
    md = render_markdown(inp)

    h2s = _h2_lines(md)
    assert "## Bloat metrics" in h2s
    assert "## Findings" in h2s

    assert "> No findings detected (no LLM hints, LLM not dispatched)." in md


# ---------------------------------------------------------------------------
# Legacy mode cases (2 rows)

def test_legacy_with_findings():
    """State-table row: legacy | ≥ 1 finding."""
    finding = Finding(
        kind="S",
        severity="MED",
        locations=[(120, 134)],
        summary="7 chained bash commands without judgement",
        refactor="extract to scripts/create-worktree.sh",
        saved_lines=10,
    )
    md = render_report(
        target=Path("/path/to/SKILL.md"),
        skill_name="example",
        total_lines=300,
        scripts_dir=None,
        findings=[finding],
        spec_path=None,
        spec_inline=None,
        host_root=None,
    )

    h2s = _h2_lines(md)
    assert "## Bloat metrics" in h2s
    assert "## Findings" in h2s
    assert "## Summary" not in h2s
    assert "## No findings" not in h2s

    h3s = _h3_lines(md)
    assert any(h.startswith("### S1 (MED)") for h in h3s)


def test_legacy_zero_findings_preserves_full_informational_text():
    """State-table row: legacy | 0 findings.

    Body has the FULL 3-line informational blockquote (V4 fix vs
    V3's single-line reduction). No `## No findings` H2 appears.
    """
    md = render_report(
        target=Path("/path/to/SKILL.md"),
        skill_name="example",
        total_lines=120,
        scripts_dir=None,
        findings=[],
        spec_path=None,
        spec_inline=None,
        host_root=None,
    )

    h2s = _h2_lines(md)
    assert "## Bloat metrics" in h2s
    assert "## Findings" in h2s
    assert "## Summary" not in h2s
    assert "## No findings" not in h2s

    assert "> No findings detected." in md
    assert "> This skill passed both detectors." in md
    assert "no redundancy" in md.lower()
    assert "scriptifiable blocks" in md.lower()
