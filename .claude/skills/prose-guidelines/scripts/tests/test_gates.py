"""Pytest cases for task-1 validator gates (G1/G2/G3-recount/G5-dedup/G6).

Each test invokes ``validate-findings.sh`` against a fixture YAML under
``fixtures/gates/`` and asserts the expected exit code + stream substring,
matching the ``test_semantic_axis.py`` convention. Expected exits/streams
are derived from the spec ``Testing`` table (docs/specs/active/
2026-06-02-prose-guidelines-reliability-hardening.md), not from the
implementation.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SKILL_ROOT = REPO_ROOT / "prose-guidelines"
VALIDATOR = SKILL_ROOT / "scripts" / "validate-findings.sh"
GATES = SKILL_ROOT / "scripts" / "tests" / "fixtures" / "gates"
TARGET = GATES / "target.md"


def _run(yaml_name: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(VALIDATOR), str(GATES / yaml_name), str(TARGET)],
        capture_output=True,
        text=True,
        check=False,
    )


# --- Gate 7 fact-token preservation (G1) ---------------------------------


def test_fact_loss_drop() -> None:
    res = _run("fact-loss-drop.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate7 drop" in res.stderr, res.stderr
    assert "findings: []" in res.stdout, res.stdout


def test_fact_preserved_pass() -> None:
    res = _run("fact-preserved-pass.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate7 drop" not in res.stderr, res.stderr
    assert "evidence_quote" in res.stdout, res.stdout


def test_cjk_negation_drop() -> None:
    res = _run("cjk-negation-drop.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate7 drop" in res.stderr, res.stderr
    assert "findings: []" in res.stdout, res.stdout


# --- Gate 7 exemption (G2) -----------------------------------------------


def test_lexical_list_exemption_pass() -> None:
    res = _run("lexical-list-exemption-pass.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate7 drop" not in res.stderr, res.stderr
    assert "evidence_quote" in res.stdout, res.stdout


def test_lexical_deletes_negation_shaped_weasel_pass() -> None:
    res = _run("lexical-deletes-negation-shaped-weasel-pass.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate7 drop" not in res.stderr, res.stderr
    assert "evidence_quote" in res.stdout, res.stdout


def test_paragraph_drops_number_drop() -> None:
    res = _run("paragraph-drops-number-drop.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate7 drop" in res.stderr, res.stderr
    assert "findings: []" in res.stdout, res.stdout


# --- Gate 8 ratio recount (G3) -------------------------------------------


def test_ratio_mismatch_drop() -> None:
    res = _run("ratio-mismatch-drop.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate8 drop" in res.stderr, res.stderr
    assert "findings: []" in res.stdout, res.stdout


def test_cjk_ratio_recount() -> None:
    res = _run("cjk-ratio-recount.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate8 drop" not in res.stderr, res.stderr
    assert "ratio: 0.6" in res.stdout, res.stdout


def test_paragraph_ratio_ge_0_8_drop() -> None:
    res = _run("paragraph-ratio-ge-0.8-drop.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "Gate8 drop" in res.stderr, res.stderr
    assert "findings: []" in res.stdout, res.stdout


# --- G5 surface-token dedup ----------------------------------------------


def test_zh_qishi_single_hit_count_1() -> None:
    res = _run("cjk-weasel-dedup-single-hit-1.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    # exactly one lexical_hits entry survives dedup
    assert res.stdout.count("token:") == 1, res.stdout


# --- G6 per-subclass severity_recount ------------------------------------


def test_lexical_3_within_subclass_high() -> None:
    res = _run("lexical-3-within-subclass-HIGH.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "severity_recount: HIGH" in res.stdout, res.stdout


def test_lexical_cross_class_caps_med() -> None:
    res = _run("lexical-cross-class-caps-MED.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "severity_recount: MED" in res.stdout, res.stdout


# --- G8 caveman just->B4 -------------------------------------------------


def test_just_b4_hit() -> None:
    res = _run("just-b4-hit.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "subclass: B4" in res.stdout, res.stdout
    assert "token: just" in res.stdout, res.stdout


# --- PR2: B5 redundant-phrase HIGH-eligible ------------------------------


def test_lexical_3_B5_high() -> None:
    # 3x B5 redundant phrases must escalate to HIGH (B5 is HIGH-eligible).
    res = _run("lexical-3-B5-HIGH.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "severity_recount: HIGH" in res.stdout, res.stdout
    assert "subclass: B5" in res.stdout, res.stdout


# --- PR2: B3 nominalization demoted to advisory (never HIGH) -------------


def test_lexical_3_B3_advisory_not_high() -> None:
    # 3x B3 nominalizations must NOT escalate to HIGH — B3 is advisory,
    # excluded from the HIGH-eligible set; it caps at MED via `total`.
    res = _run("lexical-3-B3-advisory-MED.yaml")
    assert res.returncode == 0, f"exit={res.returncode}; stderr={res.stderr!r}"
    assert "severity_recount: HIGH" not in res.stdout, res.stdout
    assert "severity_recount: MED" in res.stdout, res.stdout
    assert "subclass: B3" in res.stdout, res.stdout
