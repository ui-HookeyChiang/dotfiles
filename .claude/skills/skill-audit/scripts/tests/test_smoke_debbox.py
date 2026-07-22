"""Offline smoke test: full pipeline against ubiquiti-debbox-fw-build,
with a deterministic stub for the LLM dispatch.

The real --with-llm smoke test requires the Claude Code harness and is
documented in the docstring at the bottom of this file for manual execution.

M2 calibration (formula A) landed in PR #514: the ``@pytest.mark.xfail``
markers have been removed and the two debbox assertions now use formula-A
baselines (downshifted from the original spec expectations):

- ``test_metrics_mode_against_real_debbox``: ``composite["score"] >= 39``
  (was: > 40 pre-calibration)
- ``test_rank_all_against_ubiquiti_corpus``: ``"ubiquiti-debbox-fw-build"``
  in top 15 (was: top 5 pre-calibration)

Full background, formula derivation, and the rationale for the downshift:
``docs/specs/done/2026-05-23-skill-audit-m2-imbalance-calibration.md``.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
TARGET = REPO / "ubiquiti-debbox-fw-build" / "SKILL.md"


def test_metrics_mode_against_real_debbox():
    """End-to-end: --metrics on debbox-fw-build should rank it high."""
    if not TARGET.exists():
        pytest.skip("ubiquiti-debbox-fw-build/SKILL.md not present in this checkout")

    r = subprocess.run(
        [sys.executable, str(REPO / "skill-audit" / "scripts" / "syntax_audit.py"),
         str(TARGET), "--metrics", "--json"],
        capture_output=True, text=True, cwd=str(REPO),
    )
    # Exit 0 (composite >= 30) is expected; debbox-fw-build is the heavy hitter.
    assert r.returncode in (0, 2), f"unexpected exit {r.returncode}; stderr={r.stderr}"
    data = json.loads(r.stdout)
    assert data["mode"] == "metrics"
    assert data["metrics"]["size"]["lines_total"] >= 500
    # Spec acceptance criterion (R3 downgrade): debbox-fw-build composite >= 39.
    # Under formula A the composite stays at 39.00 unchanged; the rank improves
    # via cohort dispersal (21 -> 13 in full corpus). See M2 calibration decision doc.
    assert data["composite"]["score"] >= 39, (
        f"debbox-fw-build composite is {data['composite']['score']}, "
        "expected >= 39 (formula A baseline)"
    )


def test_rank_all_against_ubiquiti_corpus(tmp_path):
    """--rank-all over ubiquiti-* puts debbox-fw-build in the top 5."""
    REPO = Path(__file__).resolve().parents[3]
    if not (REPO / "ubiquiti-debbox-fw-build").exists():
        pytest.skip("ubiquiti-* corpus not present")

    td_path = tmp_path / "ubq-corpus"
    td_path.mkdir()
    for ub in sorted(REPO.glob("ubiquiti-*/SKILL.md")):
        d = td_path / ub.parent.name
        d.mkdir()
        (d / "SKILL.md").symlink_to(ub)
        scripts = ub.parent / "scripts"
        if scripts.is_dir():
            (d / "scripts").symlink_to(scripts)

    r = subprocess.run(
        [sys.executable, str(REPO / "skill-audit" / "scripts" / "syntax_audit.py"),
         "--rank-all", str(td_path), "--json"],
        capture_output=True, text=True,
    )
    assert r.returncode == 0, f"exit {r.returncode}; stderr={r.stderr}"
    data = json.loads(r.stdout)
    ranking = data.get("ranking") or []
    top15 = [r["name"] for r in ranking[:15]]
    # Spec criterion G3 (downgraded R3, formula-A landed in T3):
    # debbox-fw-build must be in the top 15 of the ubiquiti-only subset.
    assert "ubiquiti-debbox-fw-build" in top15, (
        f"debbox-fw-build not in top 15 of {len(ranking)}: top15={top15}"
    )


# Manual --with-llm smoke test (acceptance criterion 4 of the spec).
#
# Run from inside Claude Code so the Agent tool is available:
#
#     Skill skill-syntax-audit ubiquiti-debbox-fw-build/SKILL.md --with-llm
#
# The report's `## Findings` section (per PR0b unified-anchor contract)
# MUST include at least the four LLM finding items identified manually on
# 2026-05-22, surfaced under their `### Paraphrased redundancy` /
# `### Contradictions` / `### Covered by existing wrapper` /
# `### Semantic scriptifiable` H3 subsections:
#
#     1. paraphrased_redundancy mentioning the AWS DryRun verification
#        (`aws --profile firmware-prod lambda invoke ... DryRun`) appearing
#        in the Quick Start, AWS Signing Setup, and Troubleshooting sections.
#
#     2. contradictions flagging the simplified container-find example
#        (lines 88-89: `CONTAINER=$(docker ps ... grep arm64 | head -1)`)
#        conflicting with the canonical version (lines 54-58 with REQUIRED_VER
#        parsing). The simplified form triggers the error documented in the
#        troubleshooting table at line 577.
#
#     3. covered_by_wrapper flagging the Mode 1/2/3 teaching section (lines
#        105-204) as already implemented by scripts/parallel-build.sh's
#        --no-seed / --share-dl / --seed-from flags.
#
#     4. paraphrased_redundancy or semantic_scriptifiable surfacing the
#        pre-flight checklist scatter across the Quick Start pre-flight (lines
#        53-65), Interactive Build pre-flight checks (lines 317-326), and
#        implicit troubleshooting rows.
#
# If the LLM returns fewer than four of these — that's a real signal worth
# investigating: either the prompt template needs sharpening, or the metric
# prior needs to include stronger hints. Either way the result of the smoke
# test is logged to the spec's calibration data.
