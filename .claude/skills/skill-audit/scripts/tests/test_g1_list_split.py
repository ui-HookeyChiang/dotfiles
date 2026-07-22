"""F1 — list-item paragraph boundary acceptance tests.

All fixtures are synthetic and self-contained — they prove the splitter's
behavior without depending on any live skill's (evolving) prose.
"""
from __future__ import annotations

import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parents[1]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from detectors import g1_cross_skill_dup as g1

# All tests use self-contained synthetic fixtures — no dependency on any live
# skill's prose, which evolves (the original real dup that motivated F1 was
# itself removed as a dedup once this detector surfaced it).


# ── 1a: F1 granularity — a glued list block splits into per-item candidates ──
# What F1 fixes: a no-blank-line list collapses into ONE giant paragraph under
# the old blank-line/code-fence-only flush. After F1 each item that clears the
# word floor becomes its OWN Paragraph (eligible as a G1 candidate). Uses a
# SYNTHETIC fixture mirroring the 297-word glued-list structure — NOT the live
# flow-dev/SKILL.md, whose prose evolves (the original real dup was removed
# as a dedup once this detector surfaced it; the behavior under test is the
# splitter, not any one skill's current wording).

# A glued ordered list: no blank lines between items, each item >= 30 words so
# it survives the min-word floor on its own.
_GLUED_LIST = "\n".join([
    "Intro line that opens the block but is itself short.",
    "1. First item is deliberately long enough to clear the candidate floor: "
    "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi "
    "omicron pi rho sigma tau upsilon phi chi psi omega one two three four five.",
    "2. Second item also clears the floor on its own with distinct content: "
    "monday tuesday wednesday thursday friday saturday sunday january february "
    "march april may june july august september october november december year.",
    "3. Third item likewise stands alone above the floor here: red orange yellow "
    "green blue indigo violet black white grey brown cyan magenta scarlet teal "
    "navy lime olive maroon coral salmon khaki beige amber azure ivory jade.",
])


def test_f1_glued_list_splits_into_per_item_candidates(tmp_path):
    """After F1, a no-blank-line list block splits into one Paragraph per item
    (each >= MIN_CANDIDATE_WORDS), instead of collapsing into one monolith."""
    f = tmp_path / "glued.md"
    f.write_text(_GLUED_LIST + "\n", encoding="utf-8")
    paras = g1._parse_paragraphs(str(f))
    candidates = [p for p in paras if p.is_candidate]
    # The three long items each become their own candidate paragraph.
    assert len(candidates) >= 3, (
        f"expected >= 3 per-item candidates after split, got {len(candidates)}: "
        f"{[(p.start_line, p.end_line, p.word_count) for p in paras]}"
    )
    # No single candidate swallows all three items (the pre-F1 monolith bug).
    assert all(p.word_count < 120 for p in candidates), (
        f"a candidate is suspiciously large — items may still be fused: "
        f"{[(p.lines_field, p.word_count) for p in candidates]}"
    )


def test_f1_known_prefilter_gap_asymmetric_subspan_subthreshold(tmp_path):
    """KNOWN LIMITATION (documented, not a bug): an asymmetric sub-span dup — a
    short shared phrase embedded in a content-rich item — stays < MIN_PAIR_JACCARD
    even when both sides are correctly isolated paragraphs, because the rich
    item's unique tokens dilute set overlap. F1 (granularity) cannot recover it;
    lowering the threshold is OUT OF SCOPE (adds false positives). Recovering
    this class needs a shingle/substring prefilter (a separate future spec).
    Synthetic fixture pins the gap so a future metric change is noticed; it
    asserts the gap STILL EXISTS, not that the dup is absent.

    This replaces the earlier pin that keyed on a specific flow-dev/SKILL.md
    paragraph — that real dup was later removed as a dedup, so the pin now uses a
    self-contained fixture reproducing the same asymmetric-sub-span shape."""
    # A: the canonical short rule. B: the same rule as a sub-span inside a
    # content-rich item whose many unique tokens dilute the token-Jaccard.
    a = ("The advisor runs three agents with no word-count tiering; short specs "
         "get the same lenses as long ones.")
    b = ("Dispatch three agents in parallel regardless of word count using the "
         "deep prompt; join barrier waits for all three before printing findings; "
         "one agent failure does not block the others; parallel agents share no "
         "mutable state, results labeled partial if fewer than three returned; "
         "no word-count tiering applies to the short-spec path either.")
    jaccard = g1._token_jaccard(a, b)
    assert jaccard < g1.MIN_PAIR_JACCARD, (
        f"Jaccard={jaccard:.4f} now >= {g1.MIN_PAIR_JACCARD} — the asymmetric "
        "sub-span gap closed (prefilter changed?). Revisit the recall spec; pin stale."
    )


# ── 1b: marker-free multi-line prose → exactly ONE paragraph ─────────────────

def test_f1_marker_free_prose_single_paragraph(tmp_path):
    """A plain multi-line prose block (no list markers) must parse as exactly
    ONE Paragraph with the same line span as pre-F1 behavior."""
    prose = "\n".join([
        "This is a plain prose paragraph with no list markers whatsoever.",
        "It continues on the second line and should stay as one block.",
        "The third line adds more words to exceed the thirty word minimum.",
        "Fourth line: alpha beta gamma delta epsilon zeta eta theta iota.",
        "Fifth line ensures the block is well over the candidate floor here.",
        "Sixth line: kappa lambda mu nu xi omicron pi rho sigma tau upsilon.",
    ])
    f = tmp_path / "prose.md"
    f.write_text(prose + "\n", encoding="utf-8")

    paras = g1._parse_paragraphs(str(f))
    candidates = [p for p in paras if p.is_candidate]
    assert len(candidates) == 1, (
        f"Expected 1 candidate paragraph for marker-free prose, got {len(candidates)}: "
        f"{[(p.start_line, p.end_line) for p in candidates]}"
    )
    c = candidates[0]
    assert c.start_line == 1
    assert c.end_line == 6


# ── 1c: short list items coalesce — no sub-30-word fragments ─────────────────

def test_f1_short_list_items_coalesce(tmp_path):
    """A run of short (<30-word) list items must NOT produce sub-30-word fragment
    paragraphs. They should coalesce into one combined paragraph."""
    # Each item is ~5 words — well below MIN_CANDIDATE_WORDS=30
    short_items = "\n".join([
        "- alpha beta gamma delta",
        "- epsilon zeta eta theta",
        "- iota kappa lambda mu",
        "- nu xi omicron pi rho",
        "- sigma tau upsilon phi chi",
        "- psi omega foo bar baz",
        "- qux quux corge grault garply",
    ])
    f = tmp_path / "short_list.md"
    f.write_text(short_items + "\n", encoding="utf-8")

    paras = g1._parse_paragraphs(str(f))
    candidates = [p for p in paras if p.is_candidate]
    # Coalescing proof: no candidate should be born from a short item run.
    # Each candidate must be >= MIN_CANDIDATE_WORDS; sub-floor remnants at EOF
    # are non-candidates and acceptable.
    for p in candidates:
        assert p.word_count >= g1.MIN_CANDIDATE_WORDS, (
            f"Sub-floor candidate fragment found: L{p.start_line}-L{p.end_line} "
            f"({p.word_count} words < {g1.MIN_CANDIDATE_WORDS}). "
            "Short items must coalesce, not split into sub-floor fragments."
        )
    # Additionally: the total text of all paragraphs must contain all items
    # (no content dropped by over-eager flushing).
    all_text = " ".join(p.text for p in paras)
    assert "alpha beta" in all_text, "First item content must be preserved"
    assert "qux quux" in all_text, "Last item content must be preserved"
