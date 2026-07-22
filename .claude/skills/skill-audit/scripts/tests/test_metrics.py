"""Tests for advisory mode metrics."""
import math
from pathlib import Path
from advisory.metrics import compute_size, SizeMetric

FIXTURES = Path(__file__).parent / "fixtures"


def test_size_under_floor_scores_zero():
    """Skill under 200 lines doesn't deserve LLM time; score 0."""
    m = compute_size(FIXTURES / "small.md")
    assert isinstance(m, SizeMetric)
    assert m.lines_total < 200
    assert m.score == 0


def test_size_medium_log_scale():
    """Medium fixture is ~200 lines; score crosses 0 just above floor."""
    m = compute_size(FIXTURES / "medium.md")
    assert m.lines_total >= 200
    expected = min(100.0, math.log(m.lines_total / 200) * 30)
    assert abs(m.score - expected) < 0.1


def test_size_large_caps_at_100():
    """Large fixture (debbox-fw-build, 587+ lines) scores high but under cap."""
    m = compute_size(FIXTURES / "large.md")
    assert m.lines_total >= 500
    expected = min(100.0, math.log(m.lines_total / 200) * 30)
    assert abs(m.score - expected) < 0.1
    # Sanity: large should score noticeably higher than medium
    medium = compute_size(FIXTURES / "medium.md")
    assert m.score > medium.score


def test_size_counts_fenced_blocks():
    """SizeMetric exposes fenced_blocks count for downstream M2."""
    m = compute_size(FIXTURES / "large.md")
    assert m.fenced_blocks >= 10  # large fixture has many code blocks


import time
from advisory.metrics import (
    compute_imbalance, ImbalanceMetric,
    compute_staleness, StalenessMetric,
    compute_cross_section_hints, CrossSectionHints,
)


def test_imbalance_no_scripts_dir():
    """Skill with code blocks but no scripts/ counts ratio against 1."""
    m = compute_imbalance(FIXTURES / "medium.md", scripts_dir=None)
    assert m.scripts_count == 0
    assert m.imbalance_ratio == float(m.substantive_blocks)
    assert m.score == min(60.0, m.substantive_blocks * 4.0)


def test_imbalance_substantive_filter(tmp_path):
    """Code blocks with <3 substantive lines are excluded from numerator."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text(
        "# Test\n\n"
        "```bash\n"
        "ls\n"  # 1 line — excluded
        "```\n\n"
        "```bash\n"
        "# comment\n"
        "ls\n"  # only 1 substantive line — excluded
        "```\n\n"
        "```bash\n"
        "ls\n"
        "cd /tmp\n"
        "echo hi\n"  # 3 substantive — included
        "```\n"
    )
    m = compute_imbalance(fixture, scripts_dir=None)
    assert m.substantive_blocks == 1


def test_imbalance_with_scripts_dir(tmp_path):
    """scripts_count excludes tests/ subdir."""
    skill = tmp_path / "SKILL.md"
    skill.write_text("# Empty\n")
    scripts = tmp_path / "scripts"
    (scripts / "tests").mkdir(parents=True)
    (scripts / "foo.sh").write_text("#!/bin/bash\n")
    (scripts / "bar.py").write_text("# py\n")
    (scripts / "tests" / "test_x.sh").write_text("# excluded\n")
    m = compute_imbalance(skill, scripts_dir=scripts)
    assert m.scripts_count == 2


def test_staleness_uses_git_log_not_mtime(tmp_path, monkeypatch):
    """M3 reads `git log -1 --format=%ct`, not file mtime."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text("# x\n")
    import os
    os.utime(fixture, (time.time(), time.time()))
    old_ct = int(time.time()) - (180 * 86400)
    def fake_run(cmd, *a, **kw):
        class R: returncode = 0; stdout = f"{old_ct}\n"
        return R()
    monkeypatch.setattr("subprocess.run", fake_run)
    m = compute_staleness(fixture)
    assert m.last_modified_days >= 179
    assert m.score == min(100.0, m.last_modified_days / 1.8)


def test_staleness_recency_downweight(monkeypatch, tmp_path):
    """If meaningful edits in last 90d > 0, score *= 0.5."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text("# x\n")
    old_ct = int(time.time()) - (180 * 86400)

    call = {"n": 0}
    def fake_run(cmd, *a, **kw):
        call["n"] += 1
        class R: returncode = 0
        if call["n"] == 1:
            R.stdout = f"{old_ct}\n"
        else:
            R.stdout = (
                "abc123\n"
                " 3 files changed, 20 insertions(+), 3 deletions(-)\n"
                "def456\n"
                " 2 files changed, 50 insertions(+), 1 deletion(-)\n"
            )
        return R()
    monkeypatch.setattr("subprocess.run", fake_run)
    m = compute_staleness(fixture)
    assert m.meaningful_edits_90d > 0
    raw = min(100.0, m.last_modified_days / 1.8)
    assert abs(m.score - raw * 0.5) < 0.1


def test_staleness_no_git_returns_zero(tmp_path, monkeypatch):
    """File outside git: score 0, days = -1 sentinel."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text("# x\n")
    def fake_run(cmd, *a, **kw):
        class R: returncode = 128; stdout = ""
        return R()
    monkeypatch.setattr("subprocess.run", fake_run)
    m = compute_staleness(fixture)
    assert m.last_modified_days == -1
    assert m.score == 0.0


def test_cross_section_hints_finds_phrases_in_3_sections():
    """large.md contains 'docker exec' across 3+ H2/H3 sections."""
    h = compute_cross_section_hints(FIXTURES / "large.md")
    phrases = {p["phrase"] for p in h.phrases}
    assert any("docker exec" in p or "Docker" in p for p in phrases)


def test_cross_section_hints_ignores_code_blocks():
    """Phrases that only appear inside fenced blocks are not counted."""
    h = compute_cross_section_hints(FIXTURES / "small.md")
    assert all("tiny-skill" not in p["phrase"] for p in h.phrases)


def test_cross_section_hints_requires_at_least_3_sections():
    """A phrase appearing in 2 sections does NOT make the list."""
    h = compute_cross_section_hints(FIXTURES / "medium.md")
    for p in h.phrases:
        assert len(p["sections"]) >= 3


def test_staleness_uses_skill_md_parent_as_cwd(tmp_path, monkeypatch):
    """git log must be invoked with cwd=skill_md.parent."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text("# x\n")
    seen = {}
    def fake_run(cmd, *a, **kw):
        seen.setdefault("cwds", []).append(kw.get("cwd"))
        class R:
            returncode = 128
            stdout = ""
        return R()
    monkeypatch.setattr("subprocess.run", fake_run)
    compute_staleness(fixture)
    assert seen["cwds"][0] == fixture.parent


def test_staleness_counts_deletion_only_commits(monkeypatch, tmp_path):
    """A 15-deletion-only commit counts as meaningful (>10 line total)."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text("# x\n")
    old_ct = int(time.time()) - (180 * 86400)
    call = {"n": 0}
    def fake_run(cmd, *a, **kw):
        call["n"] += 1
        class R: returncode = 0
        if call["n"] == 1:
            R.stdout = f"{old_ct}\n"
        else:
            R.stdout = (
                "abc123\n"
                " 1 file changed, 15 deletions(-)\n"
            )
        return R()
    monkeypatch.setattr("subprocess.run", fake_run)
    m = compute_staleness(fixture)
    assert m.meaningful_edits_90d == 1


from advisory.metrics import compute_navigability, NavigabilityMetric

NAV_FIXTURES = Path(__file__).parent / "fixtures" / "navigability"


def test_navigability_zero_id_doc_scores_zero(tmp_path):
    """A doc with no ordinal IDs and no mode branches scores 0."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text(
        "# Tiny\n\n"
        "## Overview\n\n"
        "Do the thing. Then do the other thing.\n\n"
        "## Usage\n\n"
        "Run the command and read the output.\n"
    )
    m = compute_navigability(fixture)
    assert isinstance(m, NavigabilityMetric)
    assert m.ordinal_ids == 0
    assert m.score == 0.0


def test_navigability_many_ids_scores_high(tmp_path):
    """A doc dense with Phase/Step/Amendment IDs scores high."""
    body = ["# Big workflow\n"]
    for n in range(6):
        body.append(f"## Phase {n} — do stuff\n")
        body.append(f"Step {n}.1: first. Step {n}.2: second.\n")
        body.append(f"See Amendment A{n} for the exception.\n")
    fixture = tmp_path / "SKILL.md"
    fixture.write_text("\n".join(body))
    m = compute_navigability(fixture)
    assert m.ordinal_ids >= 18
    assert m.score >= 50.0


def test_navigability_ignores_ids_inside_code_fences(tmp_path):
    """Ordinal IDs that appear only inside fenced code are not counted."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text(
        "# Doc\n\n"
        "## Overview\n\n"
        "Plain prose, no landmarks.\n\n"
        "```bash\n"
        "# Phase 1 Phase 2 Step 3 Step 4 Amendment A1\n"
        "echo 'Phase 9 Step 9'\n"
        "```\n"
    )
    m = compute_navigability(fixture)
    assert m.ordinal_ids == 0
    assert m.score == 0.0


def test_navigability_counts_mode_note_scatter(tmp_path):
    """Inline 'in X mode' / 'under <ENV>' branches feed the scatter sub-signal."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text(
        "# Doc\n\n"
        "## A\n\n"
        "In parallel mode, do this. In linear mode, do that.\n\n"
        "## B\n\n"
        "Under <CI> the gate differs. In rewrite mode, scan references.\n"
    )
    m = compute_navigability(fixture)
    assert m.mode_notes >= 3
    assert m.score > 0.0


def test_navigability_under_env_only_counts_mode_notes(tmp_path):
    """under <ENV> branches alone (no 'in X mode' prose) still feed mode_notes."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text(
        "# Doc\n\n"
        "## A\n\n"
        "Runs under <SD_AUTONOMOUS> the gate auto-approves.\n"
        "Skipped under <SD_SKIP_ADVISORY> the advisory leg is skipped.\n\n"
        "## B\n\n"
        "Emit no prompt under <SD_AUTONOMOUS>.\n"
    )
    m = compute_navigability(fixture)
    assert m.mode_notes > 0


def test_navigability_regression_bad_scores_above_good():
    """Calibration anchor: flow-dev (bad) > skill-writer v2 (good)."""
    bad = compute_navigability(NAV_FIXTURES / "stack-dev-SKILL.md")
    good = compute_navigability(NAV_FIXTURES / "skill-writer-SKILL.md")
    assert bad.score > good.score


def test_staleness_counts_mixed_ins_del_commits(monkeypatch, tmp_path):
    """An 8-insertion + 5-deletion commit (total 13) is meaningful."""
    fixture = tmp_path / "SKILL.md"
    fixture.write_text("# x\n")
    old_ct = int(time.time()) - (180 * 86400)
    call = {"n": 0}
    def fake_run(cmd, *a, **kw):
        call["n"] += 1
        class R: returncode = 0
        if call["n"] == 1:
            R.stdout = f"{old_ct}\n"
        else:
            R.stdout = (
                "abc123\n"
                " 2 files changed, 8 insertions(+), 5 deletions(-)\n"
            )
        return R()
    monkeypatch.setattr("subprocess.run", fake_run)
    m = compute_staleness(fixture)
    assert m.meaningful_edits_90d == 1
