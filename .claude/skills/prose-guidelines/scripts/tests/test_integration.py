"""End-to-end integration tests for prose-guidelines reliability hardening.

Validates the cross-task contract: detect → validate-findings.sh (task 1) →
merge-findings.py (task 2), with the schema (severity_recount, lexical_hits
objects) flowing through, the prompt/SKILL rules (task 3), and the regression
fixtures (task 4) all composed. These exercise the full pipeline, not a single
gate — they are the Phase-3 regression suite kept permanently.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROSE = HERE.parent.parent  # prose-guidelines/
VALIDATE = PROSE / "scripts" / "validate-findings.sh"
MERGE = PROSE / "scripts" / "merge-findings.py"


def _write(tmp_path, name, text):
    p = tmp_path / name
    p.write_text(text, encoding="utf-8")
    return p


def _validate(yaml_path, target_path):
    return subprocess.run(
        ["bash", str(VALIDATE), str(yaml_path), str(target_path)],
        capture_output=True, text=True,
    )


def _merge(yaml_path, target_path):
    return subprocess.run(
        [sys.executable, str(MERGE), str(yaml_path), str(target_path)],
        capture_output=True, text=True,
    )


# --- E2E 1: full chain, Gate 7 fact-loss caught before merge --------------

def test_e2e_gate7_blocks_fact_loss(tmp_path):
    """A rewrite that drops an errno is dropped by the validator; the merge
    step then sees an empty findings set and produces zero apply units."""
    target = _write(tmp_path, "t.md", "# T\n\nThe service retries on ETIMEDOUT before paging the on-call team here.\n")
    findings = _write(tmp_path, "f.yaml", """\
file: "%s"
findings:
  - lines: "L3-L3"
    finding_class: paragraph
    semantic_axis: G7
    preceding_heading: "T"
    original_words: 11
    rewritten_words: 8
    ratio: 0.73
    confidence: high
    evidence_quote: |
      The service retries on ETIMEDOUT before paging the on-call team here.
    rewritten_text: |
      The service retries before paging the on-call team.
    suggested_action: tighten
summary: {total_paragraphs_scanned: 1, flagged_below_0_8: 1, high_severity_below_0_5: 0, findings_by_class: {paragraph: 1, lexical: 0, meta: 0, hedge: 0}}
""" % target)
    res = _validate(findings, target)
    # single drop under budget 3 -> exit 0, finding gone, Gate7 reason on stderr
    assert res.returncode == 0, res.stderr
    assert "Gate7 drop" in res.stderr
    assert "ETIMEDOUT" in res.stderr


# --- E2E 2: CJK ratio recount flows through validate ----------------------

def test_e2e_cjk_recount_not_split(tmp_path):
    """A Chinese paragraph compressed 5->3 ideographs recounts to 0.6, not the
    1.0 that str.split() would yield. A self-report of 0.6 therefore passes."""
    target = _write(tmp_path, "z.md", "# Z\n\n逾時中止連線機制說明在此處兩句。第二句補充細節說明。\n")
    findings = _write(tmp_path, "z.yaml", """\
file: "%s"
findings:
  - lines: "L3-L3"
    finding_class: lexical
    preceding_heading: "Z"
    original_words: 5
    rewritten_words: 3
    ratio: 1.0
    confidence: low
    lexical_hits: [{token: "其實", subclass: B4}]
    evidence_quote: |
      逾時中止連線機制說明在此處兩句。第二句補充細節說明。
    rewritten_text: |
      逾中連
    suggested_action: tighten
summary: {total_paragraphs_scanned: 1, flagged_below_0_8: 1, high_severity_below_0_5: 0, findings_by_class: {paragraph: 0, lexical: 1, meta: 0, hedge: 0}}
""" % target)
    res = _validate(findings, target)
    # reported 1.0 but CJK recount is far lower -> mismatch > 0.05 -> drop
    assert res.returncode == 0, res.stderr
    assert "Gate8 drop" in res.stderr


# --- E2E 3: validate -> merge pipeline, sentence-level meta ---------------

def test_e2e_validate_then_merge_meta_sentence_level(tmp_path):
    """meta + lexical on the same range: merge yields ONE unit, meta deletes
    its sentence, the fact-bearing remainder survives."""
    target = _write(tmp_path, "m.md",
                    "# M\n\nThis section describes the flow. The pipeline runs 3 retries on ETIMEDOUT before paging.\n")
    findings = _write(tmp_path, "m.yaml", """\
file: "%s"
findings:
  - lines: "L3-L3"
    finding_class: meta
    preceding_heading: "M"
    original_words: 14
    rewritten_words: 9
    ratio: 0.64
    confidence: high
    evidence_quote: |
      This section describes the flow.
    rewritten_text: |
      The pipeline runs 3 retries on ETIMEDOUT before paging.
    suggested_action: delete meta sentence
summary: {total_paragraphs_scanned: 1, flagged_below_0_8: 1, high_severity_below_0_5: 0, findings_by_class: {paragraph: 0, lexical: 0, meta: 1, hedge: 0}}
""" % target)
    res = _merge(findings, target)
    assert res.returncode == 0, res.stderr
    out = json.loads(res.stdout)
    assert len(out["units"]) == 1, out
    nu = out["units"][0]["new_string"]
    # the meta opener is gone but the hard facts survive
    assert "This section describes" not in nu
    assert "3" in nu and "ETIMEDOUT" in nu


# --- E2E 4: dogfood — run validator on prose-guidelines's OWN seeded fixture --

def test_e2e_dogfood_seeded_fixture_clean(tmp_path):
    """The skill's own seeded fixture must validate clean (exit 0) after the
    re-baseline — no Gate 7/8 false-drops on real curated content."""
    seeded_yaml = PROSE / "tests" / "fixtures" / "seeded-v2-agent-output.yaml"
    seeded_md = PROSE / "tests" / "fixtures" / "seeded-v2-baseline.md"
    res = _validate(seeded_yaml, seeded_md)
    assert res.returncode == 0, f"dogfood seeded regression: {res.stderr}"


# --- E2E 5: edge — empty findings, overlap rejection ----------------------

def test_e2e_empty_findings(tmp_path):
    target = _write(tmp_path, "e.md", "# E\n\nNothing to compress here at all really.\n")
    findings = _write(tmp_path, "e.yaml", 'file: "%s"\nfindings: []\nsummary: {total_paragraphs_scanned: 1, flagged_below_0_8: 0, high_severity_below_0_5: 0, findings_by_class: {paragraph: 0, lexical: 0, meta: 0, hedge: 0}}\n' % target)
    v = _validate(findings, target)
    assert v.returncode == 0, v.stderr
    m = _merge(findings, target)
    assert m.returncode == 0, m.stderr
    assert json.loads(m.stdout)["units"] == []
