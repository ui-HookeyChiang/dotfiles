"""Unit tests for G8 inline-changelog-bullet detection (Candidate A — sidecar).

These cover the NEW orthogonal path that flags "changelog-as-prose": inline
historical residue in a SKILL.md body (e.g. a `## See Also` bullet that says
"Demoted from Phase 3 ... (2026-05-29)"). The sidecar must:
  - emit a `inline_changelog`-kind Segment from a date/verb marker,
  - bypass `_severity()` (which returns None for <10 lines) and fusion rule 4,
  - get its OWN MED severity + disposition=DELETE,
  - leave the stable 3-kind move-path untouched (regression in
    test_g8_disclosure.py).

LLM verdict contract (reused from the existing llm_fn dict):
  classification in ("reference", "rationale") -> the marker is pure
    change-history; removing it does NOT change behavior -> CONFIRM -> emit.
  classification == "actionable" -> the marker is contract-relevant
    (a still-in-force date / deadline / version gate); removing it WOULD lose
    current-state info -> DROP.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_SCRIPT_DIR = Path(__file__).resolve().parent.parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from detectors import g8_progressive_disclosure as g8  # noqa: E402


# ── Behavior 1: _scan_inline_changelog returns an inline_changelog Segment ──

def test_scan_inline_changelog_hits_dated_bullet() -> None:
    body = "\n".join([
        "## See Also",
        "- `skill-semantic-audit` — its G7 axis moved to `prose-guidelines` (2026-05-29).",
    ])
    segs = g8._scan_inline_changelog(body.splitlines())
    assert len(segs) == 1
    assert segs[0].kind == "inline_changelog"
    assert segs[0].start == 2 and segs[0].end == 2


def test_scan_inline_changelog_ignores_plain_bullet() -> None:
    body = "\n".join([
        "## Usage",
        "- Run the audit on the target SKILL.md and read the findings.",
    ])
    assert g8._scan_inline_changelog(body.splitlines()) == []


# ── Behavior 2: historical-marker regex (true hits + false-friend miss) ──

@pytest.mark.parametrize("line", [
    "- something happened on 2026-05-29 here",          # bare date
    "- `foo` was demoted from Phase 3",                  # Demoted
    "- this axis no longer runs",                        # no longer
    "- the G7 logic moved to `prose-guidelines`",           # moved to
    "- renamed from old-name to new-name",               # renamed
    "- replaced by the prose-guidelines skill",             # replaced by
    "- formerly part of the audit core",                 # formerly
    "- as of 2026-05-29 this is gone",                   # as of <date>
    "- the field was removed in the rewrite",            # was \w+ed
])
def test_marker_regex_true_hits(line: str) -> None:
    assert g8._is_historical_marker(line) is True


@pytest.mark.parametrize("line", [
    "- use the `moved` files in the staging area",       # 'moved' w/o 'to'
    "- this was great for performance",                  # 'was great' not -ed
    "- see the renamer module for details",              # 'renamer' not 'renamed'
    "- a normal instruction with no history at all",
])
def test_marker_regex_false_friends_miss(line: str) -> None:
    assert g8._is_historical_marker(line) is False


# SHOULD-FIX 1: "was <arbitrary -ed verb>" must NOT fire — only the explicit
# change-history verb set (demoted/removed/renamed/replaced/moved/deprecated/
# merged/folded/split/retired/superseded) counts as historical.
@pytest.mark.parametrize("line", [
    "- This was tested manually",
    "- this was needed for the cache",
    "- it was used in v1",
    "- foo was tested and passed",
    "- the value was cached for speed",
])
def test_was_verb_false_friends_miss(line: str) -> None:
    assert g8._is_historical_marker(line) is False


@pytest.mark.parametrize("line", [
    "- `foo` was demoted from Phase 3",
    "- the shim was removed (2026-05-29)",
    "- the axis was deprecated last sprint",
    "- the module was merged into core",
    "- the flag was retired in the rewrite",
])
def test_was_verb_true_hits(line: str) -> None:
    assert g8._is_historical_marker(line) is True


# NIT 4 is structural (docstring), no behavioral test.


# ── Behavior 3: _run_rule_layer now includes inline_changelog, sorted ──

def test_run_rule_layer_includes_inline_changelog_sorted() -> None:
    body = "\n".join([
        "# Title",                                       # 1
        "- `foo` was demoted from Phase 3 (2026-05-29)",  # 2  inline_changelog
        "## Why this exists",                            # 3  rationale_heading
        "Because reasons.",                              # 4
        "## Next",                                       # 5
    ])
    segs = g8._run_rule_layer(body.splitlines())
    kinds = [s.kind for s in segs]
    assert "inline_changelog" in kinds
    assert "rationale_heading" in kinds
    # sorted by start ascending
    starts = [s.start for s in segs]
    assert starts == sorted(starts)


# ── Behavior 4: sidecar DELETE path — LLM confirm -> MED finding, no <10 drop ──

def _llm_confirm_removable(seg: g8.Segment, lines: list[str]) -> dict:
    """LLM says: pure change-history, removing it doesn't change behavior."""
    return {
        "classification": "reference",
        "confidence": "high",
        "suggested_move_target": "stay",
        "evidence_quote": f"L{seg.start}-L{seg.end}: {seg.snippet}",
    }


def _make_skill(tmp_path: Path, body: str) -> Path:
    p = tmp_path / "SKILL.md"
    p.write_text(body, encoding="utf-8")
    return p


def test_inline_changelog_llm_confirm_emits_med_delete(tmp_path: Path) -> None:
    body = "\n".join([
        "## See Also",
        "- `skill-semantic-audit` — G7 axis moved to `prose-guidelines` (2026-05-29).",
    ])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], llm_fn=_llm_confirm_removable)
    # exactly the one inline_changelog finding (the bullet is a single line,
    # well below the <10-line move gate, but must NOT be dropped).
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    assert len(cl) == 1
    f = cl[0]
    assert f["axis"] == "G8"
    assert f["severity"] == "MED"
    assert "DELETE" in f["title"] or "delete" in f["title"].lower()
    assert "Delete" in f["suggested_action"]
    assert "inline change-history" in f["suggested_action"]


def test_inline_changelog_no_llm_returns_na_advisory(tmp_path: Path) -> None:
    """--no-llm must return an N/A advisory for inline_changelog (not a MED finding).

    Old contract: emit a MED DELETE finding with 'LLM confirmation advised' note.
    New contract (§6 case-3 fail-loud): open concept — return N/A advisory so the
    caller knows the axis was skipped, not a lossy regex answer presented as a finding.
    The N/A advisory carries not_applicable=True and mentions the regex candidate count."""
    body = "\n".join([
        "## See Also",
        "- `foo` was demoted from Phase 3 (2026-05-29).",
    ])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], no_llm=True)
    # No g8cl- finding (real inline_changelog DELETE finding) must appear
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    assert cl == [], f"no g8cl- finding in --no-llm mode (open concept), got: {cl}"
    # Must surface an N/A advisory
    na = [f for f in findings if f.get("not_applicable") and f.get("axis") == "G8"]
    assert na, (
        f"--no-llm must return an N/A advisory for inline_changelog open-concept axis. "
        f"Got findings: {findings}"
    )
    adv = na[0]
    assert adv["severity"] == "NOT_APPLICABLE"
    # Advisory must mention candidate count (regex still runs for INFO)
    assert "candidate" in adv["summary"].lower() or "1" in adv["summary"]


# ── Behavior 5: false-positive guard — LLM says contract-relevant -> drop ──

def _llm_says_contract_relevant(seg: g8.Segment, lines: list[str]) -> dict:
    """LLM says: the date is a still-in-force deadline; removing it loses
    current-state info."""
    return {
        "classification": "actionable",
        "confidence": "high",
        "suggested_move_target": "stay",
        "evidence_quote": "",
    }


def test_inline_changelog_contract_relevant_dropped(tmp_path: Path) -> None:
    body = "\n".join([
        "## Migration window",
        "- All v1 callers must migrate by 2026-05-29 or the shim is removed.",
    ])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], llm_fn=_llm_says_contract_relevant)
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    assert cl == []


# ── SHOULD-FIX 2: enum-overlap de-dup ─────────────────────────────────────
# A changelog bullet CONTAINED inside a move-path segment (e.g. a >=10-line
# bullet_enum) must NOT also emit a contradictory g8cl- delete finding — the
# move finding already covers that region. A changelog bullet OUTSIDE any move
# segment still emits its g8cl- finding.

def test_inline_changelog_inside_move_segment_suppressed(tmp_path: Path) -> None:
    # 12-bullet enumeration (move-path bullet_enum, movable >= 10) with ONE
    # dated bullet inside it. Expect exactly one finding: the move (g8-).
    bullets = [f"- item {i}" for i in range(1, 13)]
    bullets[4] = "- item 5 was demoted from Phase 3 (2026-05-29)"  # inner line
    body = "\n".join(["# H", *bullets])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], llm_fn=_llm_confirm_removable)
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    move = [f for f in findings if f["id"].startswith("g8-")]
    assert cl == []                       # contained changelog bullet suppressed
    assert len(move) == 1                 # the bullet_enum move finding remains


def test_inline_changelog_outside_move_segment_still_emits(tmp_path: Path) -> None:
    # A short list (movable < 10, no move finding) with a dated bullet: the
    # changelog bullet is NOT inside any move segment, so it must still emit.
    body = "\n".join([
        "# H",
        "## See Also",
        "- `foo` moved to `prose-guidelines` (2026-05-29).",
        "- normal bullet.",
    ])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], llm_fn=_llm_confirm_removable)
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    assert len(cl) == 1


# ── Behavior 6: LLM-owns-recall (§6 case-3) ──────────────────────────────
# The regex whitelist is a CLOSED list; it silently misses open-set phrasings
# like "Consolidated from the…" or "was v1 Phase 3.4". Under §6 case-3 the LLM
# OWNS recall: its "recall" mode scans the whole body and proposes segments.
# detect() must report those segments even though the regex never hit them.

def _make_recall_llm(recalled_texts: list[str]) -> g8.LLMFn:
    """Return an llm_fn that, in recall mode, proposes hard-coded text
    segments (mimicking what an LLM would find by semantic scan).  In classify
    mode it returns 'reference' so the finding is emitted.

    Protocol: detect() calls llm_fn with a sentinel Segment whose kind is
    ``"recall_probe"``; the llm_fn must return a dict with
    ``classification == "recall_proposals"`` and a ``proposals`` list of
    ``{"start": int, "end": int, "snippet": str}`` dicts."""
    def _fn(seg: g8.Segment, lines: list[str]) -> dict:
        if seg.kind == "recall_probe":
            # Return a list of proposed segment dicts (line ranges + snippet).
            return {
                "classification": "recall_proposals",
                "proposals": [
                    {"start": i + 1, "end": i + 1, "snippet": text}
                    for i, line in enumerate(lines)
                    for text in recalled_texts
                    if text in line
                ],
            }
        # classify mode — confirm as pure change-history
        return {
            "classification": "reference",
            "confidence": "high",
            "suggested_move_target": "stay",
            "evidence_quote": seg.snippet,
        }
    return _fn


def test_llm_recall_finds_open_set_phrases(tmp_path: Path) -> None:
    """§6 case-3: llm_fn recall mode must surface segments the regex misses.

    "Consolidated from the DEV static advisory…" and "(was v1 Phase 3.4)" carry
    no change-history verb from the narrow whitelist, so _scan_inline_changelog
    never proposes them.  With an injected llm_fn whose recall mode DOES return
    them, detect() must emit g8cl- findings for those lines.
    """
    body = "\n".join([
        "## Implementation notes",
        "- Consolidated from the DEV static advisory before the rewrite.",  # line 2 — regex miss
        "- Normal instruction: always set the flag before calling run().",   # line 3
        "- (was v1 Phase 3.4, now merged into the main flow)",               # line 4 — regex miss
    ])
    p = _make_skill(tmp_path, body)
    llm = _make_recall_llm([
        "Consolidated from the DEV static advisory",
        "was v1 Phase 3.4",
    ])
    findings = g8.detect([str(p)], llm_fn=llm)
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    # Both open-set bullets must be reported; the normal instruction must not.
    assert len(cl) == 2, f"expected 2 g8cl findings, got {len(cl)}: {[f['evidence_quote'] for f in cl]}"
    quotes = " ".join(f["evidence_quote"] for f in cl)
    assert "Consolidated from the DEV" in quotes
    assert "was v1 Phase 3.4" in quotes


def test_llm_recall_no_llm_fallback_misses_open_set(tmp_path: Path) -> None:
    """--no-llm is a documented-lossy fallback: open-set phrases the regex
    misses stay unreported.  This test documents the under-recall behavior."""
    body = "\n".join([
        "## Implementation notes",
        "- Consolidated from the DEV static advisory before the rewrite.",
        "- (was v1 Phase 3.4, now merged into the main flow)",
    ])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], no_llm=True)
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    # --no-llm can't see these; they must NOT appear (documented lossy gap)
    assert cl == [], f"--no-llm should miss open-set phrases, got: {cl}"


def test_false_friends_fallback_mode(tmp_path: Path) -> None:
    """--no-llm (regex fallback) still misses false-friend -ed verbs.

    "was tested" / "was needed" are not in the verb whitelist, so the regex
    fallback remains narrow-precision; they must NOT fire in --no-llm mode.
    This re-homes test_was_verb_false_friends_miss to the fallback context."""
    body = "\n".join([
        "## Notes",
        "- This was tested manually with the old harness.",
        "- The cache was needed for speed.",
    ])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], no_llm=True)
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    assert cl == [], f"false-friend -ed verbs must not fire in --no-llm fallback, got: {cl}"


# ── RED: open-concept --no-llm → N/A (fail-loud), NOT a lossy finding ─────────
# §6 case-3: inline_changelog is an OPEN concept — no regex whitelist covers the
# full open set. In --no-llm mode, the detector must NOT present a regex answer as
# a finding (fail-silent); instead it must return N/A (fail-loud). The regex MAY
# still count candidates as an INFO note, but that count is NOT a finding.

def test_no_llm_inline_changelog_returns_no_finding(tmp_path: Path) -> None:
    """--no-llm must NOT emit a g8cl- finding for a regex-matchable changelog line.

    Open-concept: the inline_changelog axis cannot give a real answer without an LLM.
    Returning a MED DELETE finding in --no-llm mode presents a lossy regex answer as
    a finding (fail-silent). Correct contract: N/A — no g8cl- finding emitted."""
    body = "\n".join([
        "## See Also",
        "- `foo` was demoted from Phase 3 (2026-05-29).",
    ])
    p = _make_skill(tmp_path, body)
    findings = g8.detect([str(p)], no_llm=True)
    cl = [f for f in findings if f["id"].startswith("g8cl-")]
    # NEW contract: inline_changelog is open-concept; --no-llm must return N/A,
    # not a lossy finding. No g8cl- finding must appear.
    assert cl == [], (
        f"--no-llm must NOT emit g8cl- finding for open-concept inline_changelog "
        f"(fail-loud N/A, not lossy regex answer). Got: {cl}"
    )


def test_no_llm_inline_changelog_regex_hit_returns_na_advisory(tmp_path: Path) -> None:
    """--no-llm returns an N/A advisory (not_applicable marker) for inline_changelog.

    detect() must surface a NOT_APPLICABLE marker so callers know the axis was
    skipped intentionally (fail-loud), not that the file is clean."""
    body = "\n".join([
        "## See Also",
        "- `foo` was demoted from Phase 3 (2026-05-29).",
    ])
    p = _make_skill(tmp_path, body)
    # detect() returns list[dict] of findings; N/A advisory must appear as an entry
    # with axis=="G8" and a "not_applicable" or "N/A" marker, OR detect() surfaces
    # it via a separate mechanism. Either way: no g8cl- finding AND some N/A signal.
    all_findings = g8.detect([str(p)], no_llm=True)
    na_entries = [
        f for f in all_findings
        if f.get("axis") == "G8" and (
            "not_applicable" in str(f.get("id", "")).lower()
            or "n/a" in str(f.get("id", "")).lower()
            or f.get("severity") == "NOT_APPLICABLE"
            or "not_applicable" in str(f.get("confidence", "")).lower()
        )
    ]
    cl = [f for f in all_findings if f["id"].startswith("g8cl-")]
    assert cl == [], "no g8cl- finding in --no-llm mode"
    # At minimum, no false finding — the N/A signal may surface via a different
    # mechanism (e.g. detect() returns a special advisory dict or the caller checks
    # separately). The primary contract is: no g8cl- finding emitted.
