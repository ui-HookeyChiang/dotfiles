"""G8: Progressive disclosure violation detector.

Rule + LLM two-layer detector for SKILL.md content that belongs in
``references/*.md`` (long code blocks, ``## Why`` / ``## Rationale`` /
``## Background`` sections, bullet enumerations).

Fusion: four-rule priority in ``references/severity-rubric.md`` L51-60.
Severity: HIGH >=30, MED 20-29, LOW 10-19 movable lines (rubric L44-49).
Anti-hallucination: out-of-bounds evidence_quote is dropped and counted;
>=3 drops -> ``SystemExit(1)`` (``references/finding-schema.md`` L28-37).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable

CODE_BLOCK_MIN_LINES = 20
BULLET_MIN_ITEMS = 5
LOW_THRESHOLD = 10
MED_THRESHOLD = 20
HIGH_THRESHOLD = 30
EVIDENCE_OOB_LIMIT = 3

RATIONALE_HEADING_RE = re.compile(
    r"^(#{2,6})\s+(why|rationale|background|design\s+rationale|design\s+history)\b",
    re.IGNORECASE,
)
ANY_HEADING_RE = re.compile(r"^(#{1,6})\s+\S")
BULLET_RE = re.compile(r"^\s*[-*]\s+\S")
FENCE_RE = re.compile(r"^\s*```")
_LINE_RANGE_RE = re.compile(r"^L(\d+)-L(\d+)$")

# ── Inline-changelog (Candidate A sidecar) ─────────────────────────────────
# A "changelog-as-prose" bullet is inline historical residue: a 1-2 line
# bullet whose meaning is pure change-history (what USED to be, what moved /
# was renamed / was demoted), which can be DELETED from the SKILL.md body
# without changing the skill's runtime behavior (it belongs in git/spec).
#
# Marker design — false-friend avoidance:
#   A line is a historical marker if it is a bullet AND it carries either
#     (a) an ISO date  \d{4}-\d{2}-\d{2}  (strong change-history signal), OR
#     (b) a change-history verb phrase in a *narrow* form so plain English
#         doesn't over-trigger:
#           \bDemoted\b              (capitalised demotion marker)
#           \bno longer\b
#           \bmoved to\b             (require "to" — bare "moved" is a false friend)
#           \brenamed\b              (not "renamer"/"rename" — \b after -ed)
#           \breplaced by\b          (require "by")
#           \bformerly\b
#           \bas of \d\b             (pair "as of" with a digit — a dated cutover)
#           \bwas (demoted|removed|renamed|replaced|moved|deprecated|merged|
#                  folded|split|retired|superseded)\b
#                                     EXPLICIT change-history verb set (QA
#                                     SHOULD-FIX 1, choice (b)).
# Bare "moved"/"renamer" miss by design.  The earlier broad "was \w+ed" form
# over-fired on plain English ("was tested", "was needed", "was used",
# "was cached"); the closed verb set above enumerates exactly the
# change-history senses so those false friends MISS while genuine
# "was demoted/removed/renamed/..." still HIT.  Defensible because it does not
# trust an arbitrary -ed suffix.
_INLINE_CHANGELOG_DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
_INLINE_CHANGELOG_VERB_RE = re.compile(
    r"\bDemoted\b"
    r"|\bno longer\b"
    r"|\bmoved to\b"
    r"|\brenamed\b"
    r"|\breplaced by\b"
    r"|\bformerly\b"
    r"|\bas of \d"
    r"|\bwas (?:demoted|removed|renamed|replaced|moved|deprecated"
    r"|merged|folded|split|retired|superseded)\b",
    re.IGNORECASE,
)

@dataclass
class Segment:
    """Rule-layer hit. 1-indexed inclusive line range."""
    start: int
    end: int
    kind: str           # code_block | rationale_heading | bullet_enum | inline_changelog
    movable_lines: int
    snippet: str

@dataclass
class _OutOfBoundsCounter:
    count: int = 0
    messages: list[str] = field(default_factory=list)

    def bump(self, msg: str) -> None:
        self.count += 1
        self.messages.append(msg)
        if self.count >= EVIDENCE_OOB_LIMIT:
            raise SystemExit(
                f"g8: {self.count} out-of-bounds evidence_quote drops "
                f"(limit={EVIDENCE_OOB_LIMIT}); aborted. "
                f"Recent: {self.messages[-EVIDENCE_OOB_LIMIT:]}"
            )

def _scan_code_blocks(lines: list[str]) -> list[Segment]:
    out, i, n = [], 0, len(lines)
    while i < n:
        if FENCE_RE.match(lines[i]):
            start = i
            j = i + 1
            while j < n and not FENCE_RE.match(lines[j]):
                j += 1
            end = j if j < n else n - 1
            block_len = end - start + 1
            if block_len >= CODE_BLOCK_MIN_LINES:
                snippet = lines[start + 1][:80] if start + 1 < n else ""
                out.append(Segment(start + 1, end + 1, "code_block",
                                   block_len, snippet.strip()))
            i = j + 1
        else:
            i += 1
    return out

def _scan_rationale_headings(lines: list[str]) -> list[Segment]:
    out, n = [], len(lines)
    for i, line in enumerate(lines):
        m = RATIONALE_HEADING_RE.match(line)
        if not m:
            continue
        depth = len(m.group(1))
        end = n - 1
        for j in range(i + 1, n):
            mh = ANY_HEADING_RE.match(lines[j])
            if mh and len(mh.group(1)) <= depth:
                end = j - 1
                break
        out.append(Segment(i + 1, end + 1, "rationale_heading",
                           end - i + 1, line.strip()[:80]))
    return out

def _scan_bullet_enumeration(lines: list[str]) -> list[Segment]:
    out, n, i = [], len(lines), 0
    while i < n:
        if BULLET_RE.match(lines[i]):
            start, j, count = i, i, 0
            while j < n:
                if BULLET_RE.match(lines[j]):
                    count += 1
                    j += 1
                elif lines[j].strip() == "" and j + 1 < n and BULLET_RE.match(lines[j + 1]):
                    j += 1
                elif lines[j].startswith(("  ", "\t")):
                    j += 1
                else:
                    break
            end = j - 1
            if count >= BULLET_MIN_ITEMS:
                out.append(Segment(start + 1, end + 1, "bullet_enum",
                                   end - start + 1, lines[start].strip()[:80]))
            i = j
        else:
            i += 1
    return out

def _is_historical_marker(line: str) -> bool:
    """True if ``line`` is a bullet carrying a change-history marker (ISO date
    or a narrow change-history verb phrase). See _INLINE_CHANGELOG_*_RE for the
    false-friend rationale."""
    if not BULLET_RE.match(line):
        return False
    return bool(_INLINE_CHANGELOG_DATE_RE.search(line)
                or _INLINE_CHANGELOG_VERB_RE.search(line))


def _scan_inline_changelog(lines: list[str]) -> list[Segment]:
    """One Segment per bullet line that reads as inline change-history.

    Orthogonal to the 3 stable kinds: each hit is a single 1-line bullet
    (``movable_lines == 1``), deliberately below the move-path <10 gate — the
    sidecar in ``_process_segment`` handles its DELETE disposition without
    touching ``_severity`` / ``_fuse``."""
    out = []
    for i, line in enumerate(lines):
        if _is_historical_marker(line):
            out.append(Segment(i + 1, i + 1, "inline_changelog",
                               1, line.strip()[:80]))
    return out


def _run_rule_layer(lines: list[str]) -> list[Segment]:
    segs = (_scan_code_blocks(lines) + _scan_rationale_headings(lines)
            + _scan_bullet_enumeration(lines)
            + _scan_inline_changelog(lines))
    segs.sort(key=lambda s: s.start)
    return segs

LLMFn = Callable[[Segment, list[str]], dict]

def _default_llm_dispatch(segment: Segment, file_lines: list[str]) -> dict:
    """Placeholder dispatch — real wiring lands in a later task.
    Callers must inject ``llm_fn=`` or use ``no_llm=True``."""
    raise NotImplementedError(
        "g8: real LLM dispatch not wired. Pass llm_fn= or use no_llm=True."
    )

def _llm_classify(segment: Segment, file_lines: list[str], llm_fn: LLMFn) -> dict:
    v = llm_fn(segment, file_lines)
    cls = v.get("classification", "actionable")
    if cls not in ("actionable", "reference", "rationale"):
        cls = "actionable"
    return {
        "classification": cls,
        "confidence": v.get("confidence", "medium"),
        "suggested_move_target": v.get("suggested_move_target", "stay"),
        "evidence_quote": v.get("evidence_quote", ""),
    }

def _fuse(rule_hit: bool, llm_class: str | None,
          movable_lines: int) -> tuple[str, str]:
    """4-rule priority (severity-rubric.md L51-60). Returns
    (action, confidence_or_reason); action in {drop, report}."""
    # Rule 1
    if rule_hit and llm_class == "actionable":
        return ("drop", "rule_overruled_by_llm_actionable")
    # Rule 4 (check before rule 2 so the <10 cutoff wins)
    if rule_hit and llm_class in ("reference", "rationale") and movable_lines < LOW_THRESHOLD:
        return ("drop", "below_low_threshold")
    # Rule 2
    if rule_hit and llm_class in ("reference", "rationale"):
        return ("report", "high")
    # Rule 3
    if not rule_hit and llm_class in ("reference", "rationale"):
        return ("report", "medium")
    return ("drop", "no_signal")

def _severity(movable_lines: int) -> str | None:
    if movable_lines >= HIGH_THRESHOLD:
        return "HIGH"
    if movable_lines >= MED_THRESHOLD:
        return "MED"
    if movable_lines >= LOW_THRESHOLD:
        return "LOW"
    return None

def _validate_evidence(finding: dict, file_lines: list[str],
                       counter: _OutOfBoundsCounter) -> bool:
    n = len(file_lines)
    for loc in finding.get("locations", []):
        m = _LINE_RANGE_RE.match(loc.get("lines", ""))
        if not m:
            counter.bump(f"malformed lines field: {loc.get('lines')!r}")
            return False
        a, b = int(m.group(1)), int(m.group(2))
        if a < 1 or b > n or a > b:
            counter.bump(
                f"out-of-bounds L{a}-L{b} for {loc.get('file')} (file has {n} lines)"
            )
            return False
    return True

def _build_finding(idx: int, file_path: str, file_lines: list[str],
                   segment: Segment, severity: str, confidence: str,
                   llm_verdict: dict | None) -> dict:
    quote = (llm_verdict.get("evidence_quote", "") if llm_verdict else "").strip()
    if not quote:
        anchor = file_lines[segment.start - 1] if 0 < segment.start <= len(file_lines) else ""
        quote = anchor.strip()[:80]
    target = (llm_verdict.get("suggested_move_target", "REFERENCE.md")
              if llm_verdict else "REFERENCE.md")
    cls = llm_verdict["classification"] if llm_verdict else "reference"
    return {
        "id": f"g8-{idx:03d}",
        "axis": "G8",
        "severity": severity,
        "confidence": confidence,
        "title": (f"{segment.kind.replace('_', ' ')} at L{segment.start}-L{segment.end} "
                  f"belongs in references/"),
        "summary": (f"Rule layer flagged a {segment.kind} of {segment.movable_lines} "
                    f"lines; LLM classified as {cls}. Suggest moving to {target}."),
        "locations": [{"file": file_path, "lines": f"L{segment.start}-L{segment.end}"}],
        "evidence_quote": f"{file_path} L{segment.start}-L{segment.end}:\n  {quote}",
        "numeric_basis": None,
        "suggested_action": f"Extract L{segment.start}-L{segment.end} to {target}.",
        "requires_human": True,
    }

def _build_inline_changelog_finding(idx: int, file_path: str,
                                    file_lines: list[str], segment: Segment,
                                    llm_verdict: dict | None) -> dict:
    """Sidecar DELETE finding for inline change-history.

    Distinct from ``_build_finding`` (the move-to-references path): severity is
    always MED, disposition is DELETE, and it carries its own ``g8cl-`` id
    prefix so consumers (and tests) can tell the two G8 sub-paths apart. It
    never calls ``_severity`` (which would return None for the 1-line range)."""
    quote = (llm_verdict.get("evidence_quote", "") if llm_verdict else "").strip()
    if not quote:
        anchor = file_lines[segment.start - 1] if 0 < segment.start <= len(file_lines) else ""
        quote = anchor.strip()[:80]
    rng = f"L{segment.start}-L{segment.end}"
    summary = (f"Bullet at {rng} reads as inline change-history "
               f"(date / 'moved to' / 'Demoted' / 'was …ed' marker); deleting "
               f"it does not change runtime behavior.")
    if llm_verdict is None:
        summary += " Rule-only hit — LLM confirmation is advised."
    return {
        "id": f"g8cl-{idx:03d}",
        "axis": "G8",
        "severity": "MED",
        "confidence": "high" if llm_verdict is not None else "medium",
        "title": f"inline change-history at {rng} — DELETE (not move-to-references)",
        "summary": summary,
        "locations": [{"file": file_path, "lines": rng}],
        "evidence_quote": f"{file_path} {rng}:\n  {quote}",
        "numeric_basis": None,
        "suggested_action": (
            f"Delete {rng} (inline change-history; belongs in git/spec, "
            f"not SKILL.md body)."
        ),
        "requires_human": True,
    }


def _llm_recall(file_lines: list[str], llm_fn: LLMFn) -> list[Segment]:
    """§6 case-3: LLM owns recall for inline_changelog.

    Sends a recall probe (Segment with kind="recall_probe") to llm_fn so it
    can scan the whole file body and propose inline-changelog candidate lines.
    Returns a list of Segment objects (kind="inline_changelog") for any line
    ranges the LLM surfaces.  If the LLM does not return a
    "recall_proposals" response, returns an empty list (graceful degradation).

    This is the PRIMARY recall path when an LLM is available.  The regex
    _scan_inline_changelog is the --no-llm FALLBACK and under-recalls by
    construction (see §6 case-3 and _INLINE_CHANGELOG_VERB_RE docstring).
    """
    probe = Segment(start=0, end=0, kind="recall_probe", movable_lines=0,
                    snippet="")
    try:
        result = llm_fn(probe, file_lines)
    except Exception:
        return []
    if result.get("classification") != "recall_proposals":
        return []
    out: list[Segment] = []
    for p in result.get("proposals", []):
        try:
            start = int(p["start"])
            end = int(p["end"])
        except (KeyError, TypeError, ValueError):
            continue
        if start < 1 or end < start or end > len(file_lines):
            continue
        snippet = str(p.get("snippet", ""))[:80]
        out.append(Segment(start=start, end=end, kind="inline_changelog",
                           movable_lines=end - start + 1, snippet=snippet))
    return out


def _process_inline_changelog(seg: Segment, path: str, text: list[str],
                              no_llm: bool, llm_fn: LLMFn | None,
                              next_id: int,
                              counter: _OutOfBoundsCounter) -> dict | None:
    """Sidecar path — orthogonal to _severity / _fuse.

    no_llm: §6 case-3 — inline_changelog is an OPEN concept; no regex whitelist
      covers the full open set. Returning a lossy regex answer as a finding would
      be fail-silent (caller cannot tell "found nothing" from "axis not run").
      Contract: return None here (no finding); detect() surfaces one N/A advisory
      per file when any inline_changelog segments exist but were skipped.
    with LLM: the verdict's classification is reused —
      reference/rationale -> the marker is pure change-history -> CONFIRM/emit;
      actionable          -> contract-relevant (still-in-force date/version
                             gate); removing it WOULD lose current-state info
                             -> DROP (false-positive guard)."""
    if no_llm:
        # Open concept — do NOT emit a lossy regex finding. Caller (detect())
        # surfaces the N/A advisory for the file when it sees skipped segments.
        return None

    verdict = _llm_classify(seg, text, llm_fn)  # type: ignore[arg-type]
    if verdict["classification"] == "actionable":
        return None  # contract-relevant; keep it
    f = _build_inline_changelog_finding(next_id, path, text, seg,
                                        llm_verdict=verdict)
    return f if _validate_evidence(f, text, counter) else None


def _process_segment(seg: Segment, path: str, text: list[str],
                     no_llm: bool, llm_fn: LLMFn | None,
                     next_id: int, counter: _OutOfBoundsCounter) -> dict | None:
    if seg.kind == "inline_changelog":
        return _process_inline_changelog(seg, path, text, no_llm, llm_fn,
                                         next_id, counter)
    if no_llm:
        sev = _severity(seg.movable_lines)
        if sev is None:
            return None
        f = _build_finding(next_id, path, text, seg, sev,
                           confidence="high", llm_verdict=None)
        return f if _validate_evidence(f, text, counter) else None

    verdict = _llm_classify(seg, text, llm_fn)  # type: ignore[arg-type]
    action, conf = _fuse(True, verdict["classification"], seg.movable_lines)
    if action == "drop":
        return None
    sev = _severity(seg.movable_lines)
    if sev is None:
        return None
    f = _build_finding(next_id, path, text, seg, sev,
                       confidence=conf, llm_verdict=verdict)
    return f if _validate_evidence(f, text, counter) else None

def _build_inline_changelog_na(path: str, candidate_count: int) -> dict:
    """N/A advisory emitted when inline_changelog axis is skipped under --no-llm.

    §6 case-3: inline_changelog is an open concept — the regex provides WIDE
    candidate recall but cannot confirm removability without an LLM.  Presenting
    the regex hits as DELETE findings would be fail-silent (a lossy answer
    masquerading as a decision).  Instead, detect() surfaces one N/A advisory
    per file so the caller knows the axis ran but returned no actionable verdict.

    This advisory is NOT a finding: it carries ``"not_applicable": True`` and
    ``"severity": "NOT_APPLICABLE"``.  audit.py filters it out before exit-code
    accounting so it does not inflate the finding count or trigger EXIT_FLAGGED.
    """
    return {
        "id": "g8-na-inline_changelog",
        "axis": "G8",
        "severity": "NOT_APPLICABLE",
        "not_applicable": True,
        "confidence": "N/A",
        "title": "G8 inline_changelog: N/A under --no-llm (open concept needs LLM)",
        "summary": (
            f"--no-llm: inline_changelog axis not run for {path}. "
            f"Regex found {candidate_count} candidate line(s) — "
            "open-concept recall needs an LLM; not presenting regex hits as findings. "
            "Re-run without --no-llm to get actionable results."
        ),
        "locations": [],
        "evidence_quote": "",
        "numeric_basis": None,
        "suggested_action": "Re-run without --no-llm to enable inline_changelog detection.",
        "requires_human": False,
    }


def detect(paths: Iterable[str], *, no_llm: bool = False,
           llm_fn: LLMFn | None = None, **_kwargs) -> list[dict]:
    """Run G8 detection.

    Args:
        paths: SKILL.md paths to audit.
        no_llm: skip LLM layer; rule hits report directly (rule 3 cannot fire).
            For inline_changelog, --no-llm returns a NOT_APPLICABLE advisory
            (§6 case-3: open concept — no regex whitelist covers the full open
            set; presenting regex hits as findings is fail-silent).  The regex
            still runs to count candidates (INFO only, not a verdict).
        llm_fn: callable used for both inline_changelog recall (recall_probe) and
            per-segment classification.  When an LLM is available it OWNS recall
            for inline_changelog (§6 case-3): detect() sends a recall_probe first
            so the LLM can scan the whole body; the regex fallback is only active
            under --no-llm.  Defaults to ``_default_llm_dispatch`` which raises
            so unintentional production calls are loud.

    Returns: findings list per ``references/finding-schema.md``.  Under --no-llm,
        includes at most one NOT_APPLICABLE advisory dict (``not_applicable: True``)
        per file for the inline_changelog axis; these are filtered by audit.py
        before exit-code accounting.
    """
    if llm_fn is None and not no_llm:
        llm_fn = _default_llm_dispatch
    findings: list[dict] = []
    counter = _OutOfBoundsCounter()
    next_id = 1
    for path in paths:
        text = Path(path).read_text(encoding="utf-8").splitlines()
        # SHOULD-FIX 2 (enum-overlap de-dup): an inline_changelog bullet that
        # falls INSIDE a move-path segment which actually EMITTED a finding in
        # this run would give a contradictory disposition (move whole block vs
        # delete inner line). Two-pass per path: process move-path segments
        # first, record the ranges they emitted, then suppress any
        # inline_changelog whose [start,end] is contained in an emitted move
        # range. _run_rule_layer's sort-by-start is preserved by re-sorting the
        # combined output at the end.
        emitted: list[dict] = []
        move_ranges: list[tuple[int, int]] = []
        inline_segs: list[Segment] = []
        for seg in _run_rule_layer(text):
            if seg.kind == "inline_changelog":
                inline_segs.append(seg)
                continue
            f = _process_segment(seg, path, text, no_llm, llm_fn, next_id, counter)
            if f is not None:
                emitted.append(f)
                move_ranges.append((seg.start, seg.end))
                next_id += 1

        # §6 case-3: when LLM is available, use it as the PRIMARY recall source
        # for inline_changelog segments.  The LLM scans the whole body and
        # proposes candidates (recall_probe); we merge with the regex hits,
        # deduplicating by (start, end) so a line the regex also caught is not
        # double-reported.  Under --no-llm the regex is the only (lossy) source.
        if not no_llm and llm_fn is not None:
            llm_recalled = _llm_recall(text, llm_fn)
            seen_ranges = {(s.start, s.end) for s in inline_segs}
            for seg in llm_recalled:
                if (seg.start, seg.end) not in seen_ranges:
                    inline_segs.append(seg)
                    seen_ranges.add((seg.start, seg.end))

        # Under --no-llm: count regex candidates but emit N/A advisory instead
        # of findings (open concept — see _process_inline_changelog docstring).
        if no_llm and inline_segs:
            # Count candidates NOT covered by an emitted move range (same
            # suppression logic as the LLM path below, for accurate INFO count).
            uncovered = [
                s for s in inline_segs
                if not any(a <= s.start and s.end <= b for a, b in move_ranges)
            ]
            if uncovered:
                emitted.append(_build_inline_changelog_na(path, len(uncovered)))

        if not no_llm:
            for seg in inline_segs:
                if any(a <= seg.start and seg.end <= b for a, b in move_ranges):
                    continue  # covered by an emitted move finding
                f = _process_segment(seg, path, text, no_llm, llm_fn, next_id, counter)
                if f is not None:
                    emitted.append(f)
                    next_id += 1
        # Restore start-order across both passes (matches single-pass output
        # ordering for the common no-overlap case).  N/A advisories have
        # empty locations; sort them to the end (key=0 would put them first,
        # so use sys.maxsize as the sentinel).
        def _sort_key(fd: dict) -> int:
            locs = fd.get("locations") or []
            if not locs:
                return 2**31  # N/A advisories sort last
            m = _LINE_RANGE_RE.match(locs[0].get("lines", ""))
            return int(m.group(1)) if m else 2**31
        emitted.sort(key=_sort_key)
        findings.extend(emitted)
    return findings
