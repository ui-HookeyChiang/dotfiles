r"""Tests for A2 broken-links detector (spec 2026-05-29-doc-correctness, Task 1.B).

Covers 4 reference types:
  1. references/<file>.md          (referenced file under skill_dir)
  2. scripts/<file>.{sh,py,js,mjs}
  3. relative-path markdown link `]([^)]+)` (non-http, non-#, non-abs)
  4. internal anchor `]\(#slug)` matched against H2/H3 slugified set

Context-aware FP filter (2026-05-30 dogfood-driven):
  - inline-code example with keywords (`example` / `e.g.` / `Proposed` /
    `extract to` / `範例`) on same line
  - future-tense within ±5 lines (`will` / `extract to`)
  - same paragraph contains absolute path or other skill-name prefix

Render-report header substring assert (per CONTEXT.md L96).
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from syntax_audit import (  # noqa: E402
    Finding,
    detect_broken_links,
    _build_parsed_context,
    _slugify_heading,
    render_report,
)


FIXTURES = Path(__file__).parent / "fixtures" / "links"


def _run_on(name: str) -> list[Finding]:
    skill_md = FIXTURES / name / "SKILL.md"
    content = skill_md.read_text()
    ctx = _build_parsed_context(content)
    return detect_broken_links(skill_md, ctx)


# --- True positive: broken references/<file> -------------------------------

def test_broken_reference_md_emits_L():
    fs = _run_on("broken_reference")
    assert fs, "expected at least one broken-link finding"
    refs = [f for f in fs if f.kind == "L" and "references/llm-prompts/g7-prompt.md" in f.summary]
    assert refs, fs


def test_broken_script_emits_L():
    fs = _run_on("broken_script")
    refs = [f for f in fs if f.kind == "L" and "scripts/nonexistent.sh" in f.summary]
    assert refs, fs


def test_broken_relative_link_emits_L():
    fs = _run_on("broken_relative")
    refs = [f for f in fs if f.kind == "L" and "missing.md" in f.summary]
    assert refs, fs


# --- True positive: broken internal anchor ---------------------------------

def test_broken_anchor_emits_L():
    fs = _run_on("broken_anchor")
    refs = [f for f in fs if f.kind == "L" and "anchor" in f.summary.lower()]
    assert refs, fs


def test_anchor_typo_levenshtein_hint():
    """LOW severity: anchor is close to existing heading slug, suggest hint."""
    fs = _run_on("anchor_typo_hint")
    hint = [f for f in fs if f.kind == "L"
            and ("did you mean" in f.refactor.lower()
                 or "did you mean" in f.summary.lower())]
    assert hint, f"expected did-you-mean hint, got: {[(f.severity, f.summary, f.refactor) for f in fs]}"


# --- Clean baseline --------------------------------------------------------

def test_ok_fixture_no_findings():
    fs = _run_on("ok")
    assert fs == [], fs


# --- Context-aware FP filter -----------------------------------------------

def test_fp_inline_example_suppressed():
    """`scripts/foo.sh` inside backticks with 'example' on same line: skip."""
    fs = _run_on("fp_inline_example")
    bad = [f for f in fs if f.kind == "L" and "foo.sh" in f.summary]
    assert not bad, f"FP inline example leaked: {bad}"


def test_fp_proposed_extract_suppressed():
    """`scripts/<x>.sh` after 'Proposed refactor: extract to ...': skip."""
    fs = _run_on("fp_proposed_extract")
    bad = [f for f in fs if f.kind == "L"]
    assert not bad, f"FP proposed-extract leaked: {bad}"


def test_fp_future_will_suppressed():
    """Path mention with 'will' / future tense within ±5 lines: skip."""
    fs = _run_on("fp_future_will")
    bad = [f for f in fs if f.kind == "L"]
    assert not bad, f"FP future-will leaked: {bad}"


def test_fp_extract_to_suppressed():
    """'extract to scripts/<x>.sh' future-plan phrasing: skip."""
    fs = _run_on("fp_extract_to")
    bad = [f for f in fs if f.kind == "L"]
    assert not bad, f"FP extract-to leaked: {bad}"


def test_fp_cross_skill_abs_path_suppressed():
    """Path mentioned alongside absolute /home/.../skill-X/ path: skip."""
    fs = _run_on("fp_cross_skill_abs_path")
    bad = [f for f in fs if f.kind == "L"]
    assert not bad, f"FP cross-skill abs path leaked: {bad}"


def test_fp_cross_skill_name_prefix_suppressed():
    """Path mentioned with explicit other-skill name prefix: skip."""
    fs = _run_on("fp_cross_skill_name_prefix")
    bad = [f for f in fs if f.kind == "L"]
    assert not bad, f"FP cross-skill name-prefix leaked: {bad}"


# --- Regression baseline: prose-guidelines-style broken g7-prompt.md TP -------

def test_tp_prose_concise_style_emits_L():
    """Fixture mirrors prose-guidelines L195 g7-prompt.md broken: TP, must emit."""
    fs = _run_on("tp_prose_concise_g7")
    tps = [f for f in fs if f.kind == "L" and "g7-prompt.md" in f.summary]
    assert tps, fs


# --- Section-based severity routing ----------------------------------------

def test_severity_high_in_workflow_section():
    fs = _run_on("severity_in_workflow")
    paths = [f for f in fs if f.kind == "L" and "missing-workflow-ref.md" in f.summary]
    assert paths, fs
    assert paths[0].severity == "HIGH", paths


def test_severity_med_in_references_section():
    fs = _run_on("severity_in_references")
    paths = [f for f in fs if f.kind == "L" and "missing-ref.md" in f.summary]
    assert paths, fs
    assert paths[0].severity == "MED", paths


def test_severity_low_in_background_section():
    fs = _run_on("severity_in_background")
    paths = [f for f in fs if f.kind == "L" and "missing-bg.md" in f.summary]
    assert paths, fs
    assert paths[0].severity == "LOW", paths


# --- slugify helper contract -----------------------------------------------

def test_slugify_simple():
    assert _slugify_heading("## Phase 2: Detect") == "phase-2-detect"


def test_slugify_question_mark():
    assert _slugify_heading("### Why this design?") == "why-this-design"


def test_slugify_collapses_whitespace():
    assert _slugify_heading("##  Multiple   Spaces ") == "multiple-spaces"


def test_slugify_drops_punctuation():
    assert _slugify_heading("## Foo, bar & baz!") == "foo-bar--baz"


def test_slugify_mixed_case():
    assert _slugify_heading("## MixedCase Heading") == "mixedcase-heading"


# --- --skill-root: ref file resolving against true skill root (SPEC_HASH=2e7813a98c22) ---

def test_skill_root_ref_real_no_l1_with_root():
    """foo.md cites scripts/real.sh which EXISTS in true skill root.

    Without --skill-root the ref resolves against references/ (wrong) → L1 fires.
    With --skill-root pointing to the skill root the ref resolves correctly → NO L1.
    """
    skill_root = FIXTURES / "skill_root_ref_real"
    ref_md = skill_root / "references" / "foo.md"
    content = ref_md.read_text()
    ctx = _build_parsed_context(content)
    fs = detect_broken_links(ref_md, ctx, skill_root=skill_root)
    bad = [f for f in fs if f.kind == "L" and "real.sh" in f.summary]
    assert not bad, f"False L1 with --skill-root: {bad}"


def test_skill_root_ref_real_l1_fires_without_root():
    """foo.md cites scripts/real.sh — without skill_root it resolves against
    references/ dir where it does NOT exist → L1 fires (today's bug, baseline check)."""
    skill_root = FIXTURES / "skill_root_ref_real"
    ref_md = skill_root / "references" / "foo.md"
    content = ref_md.read_text()
    ctx = _build_parsed_context(content)
    fs = detect_broken_links(ref_md, ctx)  # no skill_root
    bad = [f for f in fs if f.kind == "L" and "real.sh" in f.summary]
    assert bad, "Expected L1 without skill_root (today's bug scenario), but none fired"


def test_skill_root_ref_ghost_l1_fires_with_root():
    """bar.md cites scripts/ghost.sh which DOES NOT exist even in the skill root.

    Anti-blanket-suppress: L1 MUST still fire with --skill-root when the file is absent.
    """
    skill_root = FIXTURES / "skill_root_ref_ghost"
    ref_md = skill_root / "references" / "bar.md"
    content = ref_md.read_text()
    ctx = _build_parsed_context(content)
    fs = detect_broken_links(ref_md, ctx, skill_root=skill_root)
    bad = [f for f in fs if f.kind == "L" and "ghost.sh" in f.summary]
    assert bad, f"Expected L1 for ghost.sh even with --skill-root, but none fired: {fs}"


def test_skill_root_sibling_ref_no_l1():
    """foo.md links a bare sibling `bar.md` that EXISTS at references/bar.md.

    With --skill-root the root base would resolve bar.md against the skill root
    (skill-root/bar.md, absent) and fire a false L1. The fix resolves against
    BOTH the root base AND the citing file's own dir — bar.md exists under the
    file's own dir (references/), so NO L1 must fire."""
    skill_root = FIXTURES / "skill_root_sibling"
    ref_md = skill_root / "references" / "foo.md"
    content = ref_md.read_text()
    ctx = _build_parsed_context(content)
    fs = detect_broken_links(ref_md, ctx, skill_root=skill_root)
    bad = [f for f in fs if f.kind == "L" and "bar.md" in f.summary]
    assert not bad, f"False L1 for bare sibling ref bar.md (exists at references/): {bad}"


def test_skill_root_byte_identical_on_skill_md():
    """Running detect_broken_links on SKILL.md with and without --skill-root must
    return identical findings (skill_root == SKILL.md parent → no difference)."""
    skill_root = FIXTURES / "skill_root_ref_real"
    skill_md = skill_root / "SKILL.md"
    content = skill_md.read_text()
    ctx = _build_parsed_context(content)
    fs_without = detect_broken_links(skill_md, ctx)
    fs_with = detect_broken_links(skill_md, ctx, skill_root=skill_root)
    assert fs_without == fs_with, (
        f"Results differ when skill_root == SKILL.md parent:\n"
        f"without: {fs_without}\nwith: {fs_with}"
    )


# --- render_report 5-col header --------------------------------------------

def test_render_report_includes_links_column():
    """Substring assert per CONTEXT.md L96 — not exact match."""
    md = render_report(
        target=Path("/tmp/test/SKILL.md"), skill_name="test", total_lines=10,
        scripts_dir=None, findings=[], spec_path=None,
        spec_inline=None, host_root=None,
    )
    assert "Links" in md
    # Pre-existing 4-col still present
    assert "Frontmatter" in md
    # H2 must remain "## Bloat metrics" (test_h2_anchors lockup)
    assert "## Bloat metrics" in md


def test_render_report_counts_L_findings():
    f = Finding(
        kind="L", severity="HIGH", locations=[(42, 42)],
        summary="references/missing.md not found",
        refactor="create file or update reference",
        saved_lines=0,
    )
    md = render_report(
        target=Path("/tmp/test/SKILL.md"), skill_name="test", total_lines=10,
        scripts_dir=None, findings=[f], spec_path=None,
        spec_inline=None, host_root=None,
    )
    assert "L1 (HIGH)" in md
    high_row = next(ln for ln in md.splitlines() if ln.startswith("| HIGH"))
    # 5 data cols now: R | S | I | F | L. HIGH row should show 1 somewhere.
    assert "| 1 |" in high_row
