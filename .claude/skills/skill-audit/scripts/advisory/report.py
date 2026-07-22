"""Advisory mode report rendering — Markdown (default) + JSON."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from .metrics import (
    SizeMetric, ImbalanceMetric, StalenessMetric, NavigabilityMetric,
    CrossSectionHints,
)
from .llm_dispatch import LLMResult, LLMStatus
from .ranker import RankedSkill


@dataclass
class ReportInput:
    target: Path
    mode: str  # "metrics" | "metrics-with-llm" | "rank-all"
    size: SizeMetric
    imbalance: ImbalanceMetric
    staleness: StalenessMetric
    navigability: NavigabilityMetric
    hints: CrossSectionHints
    composite: float
    threshold: int
    llm_result: LLMResult | None = None
    ranking: list[RankedSkill] | None = None
    failed_dispatches: list[tuple[str, str]] = field(default_factory=list)
    skill_name: str = ""


def exit_code_preview(composite: float, threshold: int) -> int:
    return 0 if composite >= threshold else 2


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def render_markdown(inp: ReportInput) -> str:
    name = inp.skill_name or inp.target.parent.name
    lines: list[str] = []
    lines.append(f"# skill-audit advisory report: {name}")
    lines.append("")
    lines.append(f"**Target**: `{inp.target}`")
    lines.append(f"**Generated**: {_now_iso()}")
    lines.append(f"**Mode**: {inp.mode}")
    lines.append("")
    lines.append("## Bloat metrics")
    lines.append("")
    lines.append("| Signal | Raw value | Score | Weight |")
    lines.append("|---|---|---|---|")
    lines.append(f"| Size | {inp.size.lines_total} lines, {inp.size.fenced_blocks} fenced blocks | {inp.size.score:.0f} | 0.32 |")
    lines.append(f"| Imbalance | {inp.imbalance.substantive_blocks} substantive blocks / {inp.imbalance.scripts_count} scripts = ratio {inp.imbalance.imbalance_ratio:.2f} | {inp.imbalance.score:.0f} | 0.32 |")
    stale_extra = f", {inp.staleness.meaningful_edits_90d} meaningful edits in 90d" if inp.staleness.meaningful_edits_90d else ""
    lines.append(f"| Staleness | {inp.staleness.last_modified_days} days{stale_extra} | {inp.staleness.score:.0f} | 0.16 |")
    lines.append(f"| Navigability | {inp.navigability.ordinal_ids} ordinal IDs, {inp.navigability.mode_notes} mode notes (span {inp.navigability.line_span}) | {inp.navigability.score:.0f} | 0.20 |")
    lines.append(f"| **Composite** | weighted blend | **{inp.composite:.0f}** | — |")
    lines.append("")
    lines.append(f"**Exit code (preview)**: {exit_code_preview(inp.composite, inp.threshold)} "
                 f"({'composite ≥ ' + str(inp.threshold) if inp.composite >= inp.threshold else 'composite < ' + str(inp.threshold)})")
    lines.append("")

    # Single guaranteed-emit `## Findings` H2 with state-aware body, per
    # spec 2026-05-27-syntax-audit-unified-mode §Design state table.
    has_hints = bool(inp.hints.phrases)
    llm_ok_with_items = (
        inp.llm_result is not None
        and inp.llm_result.status == LLMStatus.OK
        and any(
            inp.llm_result.findings.get(k)
            for k in ("paraphrased_redundancy", "semantic_scriptifiable",
                      "contradictions", "covered_by_wrapper",
                      "behavior_mismatch", "provenance_citation")
        )
    )
    llm_failed = (
        inp.llm_result is not None
        and inp.llm_result.status not in (LLMStatus.OK, LLMStatus.NOT_DISPATCHED)
    )
    llm_ok_empty = (
        inp.llm_result is not None
        and inp.llm_result.status == LLMStatus.OK
        and not llm_ok_with_items
    )

    lines.append("## Findings")
    lines.append("")

    if has_hints:
        lines.append("### Cross-section hints (LLM prior, not scored)")
        lines.append("")
        for p in inp.hints.phrases[:20]:
            secs = ", ".join(p["sections"])
            lines.append(f"- `{p['phrase']}` appears in: {secs}")
        lines.append("")

    if llm_ok_with_items:
        for key, label in (
            ("paraphrased_redundancy", "Paraphrased redundancy"),
            ("semantic_scriptifiable", "Semantic scriptifiable"),
            ("contradictions", "Contradictions"),
            ("covered_by_wrapper", "Covered by existing wrapper"),
            ("behavior_mismatch", "Behavior mismatch"),
            ("provenance_citation", "Provenance citation"),
        ):
            items = inp.llm_result.findings.get(key, [])
            if not items:
                continue
            lines.append(f"### {label} ({len(items)})")
            lines.append("")
            for f in items:
                locs = ", ".join(str(l) for l in (f.get("locations") or f.get("skill_lines") or []))
                kind_tag = f" [{f['kind']}]" if f.get("kind") else ""
                lines.append(f"- **{f.get('severity', 'N/A')}**{kind_tag} — lines {locs}: {f.get('summary', '')}")
                if "refactor" in f:
                    lines.append(f"  - Refactor: {f['refactor']}")
                if "removal_suggestion" in f:
                    lines.append(f"  - Suggestion: {f['removal_suggestion']}")
                if str(f.get("target_fully_inline", "")).lower() == "false":
                    lines.append("  - Keep: cited spec may carry a contract not inline — human review")
                if "wrapper" in f:
                    lines.append(f"  - Wrapper: `{f['wrapper']}`")
                if "saved_lines" in f:
                    lines.append(f"  - Saved: ~{f['saved_lines']} lines")
                if "drift_note" in f:
                    lines.append(f"  - Drift: {f['drift_note']}")
                # Loud-empty sentinel only (kind=stale, judge confirmed none):
                # identified by removal_suggestion == "keep". Never label a
                # confirmed finding "0 confirmed".
                if ("drift_candidates_seen" in f
                        and f.get("removal_suggestion") == "keep"):
                    lines.append(
                        f"  - Stale-drift: {f['drift_candidates_seen']} "
                        f"candidates seen, 0 confirmed"
                    )
            lines.append("")
    elif llm_failed:
        lines.append(f"### LLM dispatch failed ({inp.llm_result.status.value})")
        lines.append("")
        lines.append("Error: " + (inp.llm_result.error or "(none)"))
        if inp.llm_result.raw_response:
            lines.append("")
            lines.append("Raw response (first 500 chars):")
            lines.append("```")
            lines.append(inp.llm_result.raw_response[:500])
            lines.append("```")
        lines.append("")

    # Degenerate body — fired only when no subsection was emitted.
    if not has_hints and not llm_ok_with_items and not llm_failed:
        if llm_ok_empty:
            lines.append("> No findings detected (LLM dispatched but returned no findings).")
        else:
            lines.append("> No findings detected (no LLM hints, LLM not dispatched).")
        lines.append("")

    if inp.failed_dispatches:
        lines.append("## Failed LLM dispatches (batch)")
        lines.append("")
        lines.append("| Skill | Failure |")
        lines.append("|---|---|")
        for name_, kind in inp.failed_dispatches:
            lines.append(f"| {name_} | {kind} |")
        lines.append("")

    if inp.ranking:
        lines.append("## Full ranking")
        lines.append("")
        lines.append("| Rank | Skill | Size | Imbalance | Staleness | Navigability | Composite |")
        lines.append("|---|---|---|---|---|---|---|")
        for i, r in enumerate(inp.ranking, start=1):
            lines.append(f"| {i} | {r.name} | {r.size:.0f} | {r.imbalance:.0f} | {r.staleness:.0f} | {r.navigability:.0f} | {r.composite:.0f} |")
        lines.append("")

    return "\n".join(lines)


def render_json(inp: ReportInput) -> str:
    data = {
        "version": 1,
        "metrics_version": 3,
        "target": str(inp.target),
        "generated_at": _now_iso(),
        "mode": inp.mode,
        "metrics": {
            "size": {
                "lines_total": inp.size.lines_total,
                "lines_prose": inp.size.lines_prose,
                "bytes_total": inp.size.bytes_total,
                "fenced_blocks": inp.size.fenced_blocks,
                "score": round(inp.size.score, 2),
            },
            "imbalance": {
                "substantive_blocks": inp.imbalance.substantive_blocks,
                "scripts_count": inp.imbalance.scripts_count,
                "ratio": round(inp.imbalance.imbalance_ratio, 3),
                "score": round(inp.imbalance.score, 2),
            },
            "staleness": {
                "last_modified_days": inp.staleness.last_modified_days,
                "meaningful_edits_90d": inp.staleness.meaningful_edits_90d,
                "score": round(inp.staleness.score, 2),
            },
            "navigability": {
                "ordinal_ids": inp.navigability.ordinal_ids,
                "mode_notes": inp.navigability.mode_notes,
                "line_span": inp.navigability.line_span,
                "score": round(inp.navigability.score, 2),
            },
        },
        "cross_section_hints": inp.hints.phrases,
        "composite": {
            "score": round(inp.composite, 2),
            "weights": {"size": 0.32, "imbalance": 0.32, "staleness": 0.16, "navigability": 0.20},
            "exit_code_preview": exit_code_preview(inp.composite, inp.threshold),
        },
        "llm_findings": inp.llm_result.findings if (inp.llm_result and inp.llm_result.status == LLMStatus.OK) else {},
        "llm_status": (inp.llm_result.status.value if inp.llm_result else LLMStatus.NOT_DISPATCHED.value),
        "ranking": [
            {
                "name": r.name,
                "composite": round(r.composite, 2),
                "size": round(r.size, 2),
                "imbalance": round(r.imbalance, 2),
                "staleness": round(r.staleness, 2),
                "navigability": round(r.navigability, 2),
            } for r in (inp.ranking or [])
        ] or None,
        "failed_dispatches": [
            {"skill": n, "failure": k} for n, k in inp.failed_dispatches
        ],
    }
    return json.dumps(data, indent=2)
