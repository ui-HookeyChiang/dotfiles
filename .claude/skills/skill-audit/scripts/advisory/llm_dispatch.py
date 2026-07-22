"""Advisory LLM dispatch — spawn Explore subagent, parse YAML response.

The actual subagent spawn is delegated to a callable supplied by the caller.
audit.py wires the real `Agent` tool call; tests inject a stub function.
This separation keeps the module pure-Python + testable without a live LLM.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Callable

from .yaml_lite import parse_yaml, YamlParseError


class LLMStatus(Enum):
    OK = "ok"
    PARSE_FAIL = "LLM_PARSE_FAIL"
    SPAWN_FAIL = "LLM_SPAWN_FAIL"
    TIMEOUT = "LLM_TIMEOUT"
    NOT_DISPATCHED = "not_dispatched"


@dataclass
class LLMResult:
    status: LLMStatus
    findings: dict = field(default_factory=dict)
    raw_response: str = ""
    error: str = ""


def _render_prompt(template_path: Path, skill_path: Path, metrics_brief: str) -> str:
    template = template_path.read_text()
    return (template
            .replace("{METRICS_BRIEF}", metrics_brief)
            .replace("{SKILL_PATH}", str(skill_path)))


def dispatch_llm_audit(
    skill_md: Path,
    metrics_brief: str,
    spawn: Callable[[str], str],
    template_path: Path | None = None,
) -> LLMResult:
    """Dispatch an Explore subagent to audit one SKILL.md.

    `spawn(prompt: str) -> str` is the subagent contract. It returns the
    raw response text (expected to be YAML). Any exception from `spawn`
    is treated as a spawn failure. The real implementation in audit.py
    wires the Agent tool call; tests inject a deterministic stub.

    Timeout enforcement is the caller's responsibility. This function
    never returns LLMStatus.TIMEOUT — audit.py wraps the call with
    timing logic and rewrites the status if needed.
    """
    if template_path is None:
        template_path = Path(__file__).parents[2] / "references" / "llm-audit-prompt.md"

    if not template_path.exists():
        # Missing template is a precondition/config error, not a spawn failure —
        # we never reach the spawn step. NOT_DISPATCHED keeps logs/reports honest.
        return LLMResult(
            status=LLMStatus.NOT_DISPATCHED,
            error=f"LLM prompt template not found: {template_path}",
        )

    prompt = _render_prompt(template_path, skill_md, metrics_brief)

    try:
        raw = spawn(prompt)
    except Exception as e:  # broad catch is intentional — spawn is opaque
        return LLMResult(status=LLMStatus.SPAWN_FAIL, error=str(e))

    try:
        findings = parse_yaml(raw)
    except YamlParseError as e:
        return LLMResult(status=LLMStatus.PARSE_FAIL, raw_response=raw, error=str(e))

    # Normalize: ensure all six keys exist and are lists.
    # behavior_mismatch is the former legacy_marker (kind=removed|unbuilt);
    # provenance_citation (B-prov) is new. We still accept a stale `legacy_marker`
    # key from an old prompt/response and fold it into behavior_mismatch.
    if "legacy_marker" in findings and "behavior_mismatch" not in findings:
        findings["behavior_mismatch"] = findings.pop("legacy_marker")
    for key in ("paraphrased_redundancy", "semantic_scriptifiable",
                "contradictions", "covered_by_wrapper", "behavior_mismatch",
                "provenance_citation"):
        findings.setdefault(key, [])
        if not isinstance(findings[key], list):
            findings[key] = []

    # kind=stale severity cap: a drift finding must never auto-delete prose
    # (it may be the only evidence a feature regressed). Clamp safe-remove
    # down to consider-removing. See spec 2026-06-23-skill-audit-stale-doc-drift.
    for item in findings.get("behavior_mismatch", []):
        if isinstance(item, dict) and item.get("kind") == "stale":
            for fld in ("removal_suggestion", "refactor"):
                if item.get(fld) == "safe-remove":
                    item[fld] = "consider-removing"

    return LLMResult(status=LLMStatus.OK, findings=findings, raw_response=raw)
