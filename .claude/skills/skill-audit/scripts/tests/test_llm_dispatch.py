"""Tests for advisory LLM dispatch with a stubbed subagent."""
import pytest
from pathlib import Path
from advisory.llm_dispatch import (
    dispatch_llm_audit, LLMResult, LLMStatus,
)


CANNED_YAML = """\
paraphrased_redundancy:
  - locations: [62-64, 249-251]
    summary: "AWS DryRun in 3 sections"
    severity: MED
    refactor: "extract scripts/verify-aws-signer.sh"
    saved_lines: 10
semantic_scriptifiable: []
contradictions: []
covered_by_wrapper: []
"""


def test_dispatch_with_stub_returns_findings(tmp_path):
    skill = tmp_path / "SKILL.md"
    skill.write_text("# stub\n")
    def stub_spawn(prompt: str) -> str:
        return CANNED_YAML
    result = dispatch_llm_audit(skill, metrics_brief="brief", spawn=stub_spawn)
    assert isinstance(result, LLMResult)
    assert result.status == LLMStatus.OK
    assert len(result.findings["paraphrased_redundancy"]) == 1
    assert result.findings["paraphrased_redundancy"][0]["severity"] == "MED"


def test_dispatch_parse_failure_returns_parse_fail(tmp_path):
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    def bad_stub(prompt):
        return "this is not yaml at all just prose"
    result = dispatch_llm_audit(skill, metrics_brief="brief", spawn=bad_stub)
    assert result.status == LLMStatus.PARSE_FAIL
    assert result.raw_response == "this is not yaml at all just prose"


def test_dispatch_spawn_failure(tmp_path):
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    def failing_spawn(prompt):
        raise RuntimeError("agent spawn failed")
    result = dispatch_llm_audit(skill, metrics_brief="brief", spawn=failing_spawn)
    assert result.status == LLMStatus.SPAWN_FAIL


def test_dispatch_renders_prompt_with_metrics_brief(tmp_path):
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    seen_prompt = {}
    def capture(prompt):
        seen_prompt["text"] = prompt
        return CANNED_YAML
    dispatch_llm_audit(skill, metrics_brief="custom-brief-content", spawn=capture)
    assert "custom-brief-content" in seen_prompt["text"]
    assert str(skill) in seen_prompt["text"]


def test_dispatch_path_with_brief_placeholder_chars(tmp_path):
    """A skill_path containing '{METRICS_BRIEF}' must not corrupt the brief substitution."""
    weird_dir = tmp_path / "{METRICS_BRIEF}"
    weird_dir.mkdir()
    skill = weird_dir / "SKILL.md"
    skill.write_text("# x\n")
    seen = {}
    def capture(prompt):
        seen["text"] = prompt
        return "paraphrased_redundancy: []\n"
    dispatch_llm_audit(skill, metrics_brief="REAL-BRIEF-CONTENT", spawn=capture)
    # The literal brief content must appear; the skill_path must appear unmangled
    assert "REAL-BRIEF-CONTENT" in seen["text"]
    assert str(skill) in seen["text"]
    # The brief placeholder must have been substituted, not present as a literal
    assert "{METRICS_BRIEF}" not in seen["text"].replace(str(skill), "")


def test_dispatch_coerces_non_list_finding_to_empty(tmp_path):
    """LLM returns paraphrased_redundancy as a scalar → coerced to []."""
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    def bad_stub(prompt):
        return "paraphrased_redundancy: 5\nsemantic_scriptifiable: []\ncontradictions: []\ncovered_by_wrapper: []\n"
    r = dispatch_llm_audit(skill, metrics_brief="x", spawn=bad_stub)
    assert r.status == LLMStatus.OK
    assert r.findings["paraphrased_redundancy"] == []


def test_dispatch_includes_new_keys_when_omitted_by_llm(tmp_path):
    """When the LLM omits behavior_mismatch / provenance_citation entirely,
    the normalization pass must still inject each as an empty list. Guards
    the tuple membership (not just YAML pre-population).
    """
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    def stub_spawn(prompt: str) -> str:
        return (
            "paraphrased_redundancy: []\n"
            "semantic_scriptifiable: []\n"
            "contradictions: []\n"
            "covered_by_wrapper: []\n"
        )
    result = dispatch_llm_audit(skill, metrics_brief="brief", spawn=stub_spawn)
    assert result.status == LLMStatus.OK
    assert result.findings["behavior_mismatch"] == []
    assert result.findings["provenance_citation"] == []


def test_dispatch_folds_stale_legacy_marker_into_behavior_mismatch(tmp_path):
    """Back-compat: a stale `legacy_marker` key from an old prompt/response is
    folded into `behavior_mismatch` (the rename), preserving the items."""
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    canned = (
        "paraphrased_redundancy: []\n"
        "legacy_marker:\n"
        "  - locations: [42-42]\n"
        "    summary: '(deprecated) marker on line 42'\n"
        "    kind: removed\n"
        "    severity: HIGH\n"
        "    removal_suggestion: safe-remove\n"
    )
    result = dispatch_llm_audit(skill, metrics_brief="brief", spawn=lambda p: canned)
    assert result.status == LLMStatus.OK
    assert "legacy_marker" not in result.findings
    assert len(result.findings["behavior_mismatch"]) == 1
    assert result.findings["behavior_mismatch"][0]["kind"] == "removed"


def test_dispatch_passes_behavior_mismatch_findings_through(tmp_path):
    """behavior_mismatch findings survive normalization with kind + subtype
    fields intact."""
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    canned = (
        "paraphrased_redundancy: []\n"
        "semantic_scriptifiable: []\n"
        "contradictions: []\n"
        "covered_by_wrapper: []\n"
        "behavior_mismatch:\n"
        "  - locations: [42-42]\n"
        "    summary: 'Future Phase 0 will refuse X'\n"
        "    kind: unbuilt\n"
        "    severity: MED\n"
        "    removal_suggestion: consider-removing\n"
        "    keep_reason: ''\n"
        "provenance_citation: []\n"
    )
    result = dispatch_llm_audit(skill, metrics_brief="brief", spawn=lambda p: canned)
    assert result.status == LLMStatus.OK
    assert len(result.findings["behavior_mismatch"]) == 1
    finding = result.findings["behavior_mismatch"][0]
    assert finding["kind"] == "unbuilt"
    assert finding["removal_suggestion"] == "consider-removing"


def test_dispatch_passes_provenance_citation_through(tmp_path):
    """provenance_citation findings survive with the keep-judge field intact."""
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    canned = (
        "paraphrased_redundancy: []\n"
        "provenance_citation:\n"
        "  - locations: [10-10]\n"
        "    summary: '(per docs/specs/done/X.md) citation'\n"
        "    severity: LOW\n"
        "    target_fully_inline: false\n"
        "    keep_reason: 'cited spec may carry a live contract'\n"
    )
    result = dispatch_llm_audit(skill, metrics_brief="brief", spawn=lambda p: canned)
    assert result.status == LLMStatus.OK
    assert len(result.findings["provenance_citation"]) == 1
    # yaml_lite keeps scalars as strings (no bool coercion) — the report renderer
    # compares against the string, so assert the parsed string form here.
    assert result.findings["provenance_citation"][0]["target_fully_inline"] == "false"


def test_dispatch_coerces_non_list_behavior_mismatch_to_empty(tmp_path):
    """LLM returns behavior_mismatch as a scalar → coerced to []."""
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    def bad_stub(prompt):
        return (
            "paraphrased_redundancy: []\n"
            "behavior_mismatch: 7\n"
            "provenance_citation: 9\n"
        )
    r = dispatch_llm_audit(skill, metrics_brief="x", spawn=bad_stub)
    assert r.status == LLMStatus.OK
    assert r.findings["behavior_mismatch"] == []
    assert r.findings["provenance_citation"] == []
