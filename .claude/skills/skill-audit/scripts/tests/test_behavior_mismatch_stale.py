"""Plumbing tests for the kind=stale behavior_mismatch sub-detector.

These do NOT exercise a live LLM — `spawn` is a stub returning canned YAML.
They lock the severity clamp + render + loud-empty distinction. The
behavioral lock (does the axis FIRE on real drift) is the canary fixture,
run by the probabilistic leg in Phase 3 skill-flow.
"""
from pathlib import Path
from advisory.llm_dispatch import dispatch_llm_audit, LLMStatus


def _stub(yaml_text):
    return lambda prompt: yaml_text


def test_stale_safe_remove_is_clamped(tmp_path):
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    canned = (
        "paraphrased_redundancy: []\n"
        "semantic_scriptifiable: []\n"
        "contradictions: []\n"
        "covered_by_wrapper: []\n"
        "behavior_mismatch:\n"
        "  - locations: [10-10]\n"
        "    summary: phantom validate.py\n"
        "    kind: stale\n"
        "    severity: HIGH\n"
        "    refactor: safe-remove\n"
        "    removal_suggestion: safe-remove\n"
        "    drift_note: prose-stale; scripts/validate.py absent\n"
        "provenance_citation: []\n"
    )
    r = dispatch_llm_audit(skill, "", _stub(canned), template_path=skill)
    assert r.status == LLMStatus.OK
    item = r.findings["behavior_mismatch"][0]
    assert item["removal_suggestion"] == "consider-removing"
    assert item["refactor"] == "consider-removing"


def test_removed_safe_remove_is_untouched(tmp_path):
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    canned = (
        "behavior_mismatch:\n"
        "  - locations: [5-5]\n"
        "    summary: deprecated marker\n"
        "    kind: removed\n"
        "    severity: HIGH\n"
        "    refactor: safe-remove\n"
        "    removal_suggestion: safe-remove\n"
    )
    r = dispatch_llm_audit(skill, "", _stub(canned), template_path=skill)
    item = r.findings["behavior_mismatch"][0]
    assert item["removal_suggestion"] == "safe-remove"
    # The clamp must NOT widen to kind=removed's refactor field either.
    assert item["refactor"] == "safe-remove"


def test_unbuilt_safe_remove_is_untouched(tmp_path):
    """kind=unbuilt passes through unclamped — the clamp guard is
    kind == "stale" only. (unbuilt's own MED cap is the prompt's job.)"""
    skill = tmp_path / "SKILL.md"
    skill.write_text("# x\n")
    canned = (
        "behavior_mismatch:\n"
        "  - locations: [7-7]\n"
        "    summary: planned feature note\n"
        "    kind: unbuilt\n"
        "    severity: HIGH\n"
        "    refactor: safe-remove\n"
        "    removal_suggestion: safe-remove\n"
    )
    r = dispatch_llm_audit(skill, "", _stub(canned), template_path=skill)
    item = r.findings["behavior_mismatch"][0]
    assert item["removal_suggestion"] == "safe-remove"
    assert item["refactor"] == "safe-remove"
