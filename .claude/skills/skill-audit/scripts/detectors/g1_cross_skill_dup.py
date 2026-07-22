"""G1: File-agnostic same-meaning paragraph duplication detector.

Public API: ``detect(paths, *, no_llm=False, llm_dispatch=None, corpus_dir=None)``
    Returns list[dict] of findings per ``references/finding-schema.md``.

LLM dispatch contract (called once per candidate paragraph pair):
    Input  dict: {paragraph_a: {file, lines, text}, paragraph_b: {file, lines, text}}
    Output dict: {is_paraphrased: bool, confidence: high|medium|low,
                  carries_divergent_value?: bool,
                  evidence_a: "L<s>-L<e>", evidence_b: "L<s>-L<e>",
                  evidence_quote_a?: str, evidence_quote_b?: str,
                  reasoning?: str}

Anti-hallucination (``references/finding-schema.md`` L27-37):
    * For every positive judgment, ``evidence_a`` / ``evidence_b`` line ranges
      must lie inside the cited file and (if provided) ``evidence_quote_a/b``
      must be a literal substring of the corresponding paragraph text.
    * Invalid judgments are dropped (stderr warning + drop counter++).
    * On reaching ``_drop_limit`` failures (default 3) in one ``detect()``
      call, ``RuntimeError`` is raised so ``audit.py`` can catch and exit 1.

Severity (severity-rubric.md L9-14): HIGH = >=3 skills; MED = 2 skills
AND shared content >= 10 lines; LOW = 2 skills AND < 10 lines.

Word-floor: ``MIN_CANDIDATE_WORDS = 30`` follows spec L168 ("≥ 30 詞 / ≥ 5 行").
This is deliberately *not* the G7 floor (spec L203: ≥ 80 words OR ≥ 3 sentences) —
the two axes have different floors by design (G7 measures prose density on a
single paragraph, G1 measures cross-skill semantic dup on shorter chunks).

Intra-file pairs: G1 now also judges paragraph pairs within a single file.
Same-file findings carry a ``disposition`` field:
  ``merge``             — paraphrase, no divergent values; safe to consolidate.
  ``divergent-hazard``  — paraphrase but differing values/constraints/numbers;
                          do NOT merge without human review.
Cross-file findings: ``disposition`` is absent (null).

Jaccard prefilter: pairs with token-Jaccard < MIN_PAIR_JACCARD are skipped
before reaching the LLM (cost control for intra-file N²).
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional

class G1InsufficientContentError(ValueError):
    """G1 had < 2 candidate paragraphs to compare — an advisory N/A
    ("not enough qualifying content to analyze") condition, NOT a tool failure.

    Subclasses ValueError for back-compat: existing ``except ValueError`` callers
    keep catching it. semantic_audit.py catches THIS specifically to map the N/A
    case to a clean exit (2), while a plain ValueError (e.g. invalid corpus_dir)
    stays a genuine error (exit 1). Discriminating by type, not by message text.
    """


MIN_CANDIDATE_WORDS = 30  # spec L168 — G1 hard floor, NOT a G7-style 80
MED_LINE_THRESHOLD = 10
MIN_PAIR_JACCARD = 0.25  # Jaccard prefilter threshold (token overlap).
# Spec default is 0.3; set to 0.25 so that real-candidate pairs at the
# 0.28-0.30 boundary (synonym-heavy same-topic paraphrases) are not silently
# dropped. Stacking-dev verified cut (6 pairs at ≥ 0.3) still holds at 0.25.
_CODE_FENCE = re.compile(r"^\s*```")
_LIST_MARKER = re.compile(r"^\s*(?:\d+[.)]\s|\s*[-*+]\s|\|)")
_LINE_RANGE_RE = re.compile(r"^L(\d+)-L(\d+)$")
_TOKEN_RE = re.compile(r"[a-z0-9]+")


def _token_jaccard(text_a: str, text_b: str) -> float:
    """Token-Jaccard similarity between two texts (lowercased [a-z0-9]+ tokens)."""
    a = set(_TOKEN_RE.findall(text_a.lower()))
    b = set(_TOKEN_RE.findall(text_b.lower()))
    if not a and not b:
        return 0.0
    return len(a & b) / len(a | b)


@dataclass(frozen=True)
class Paragraph:
    """One prose paragraph extracted from a markdown file."""

    file: str
    start_line: int
    end_line: int
    text: str
    word_count: int

    @property
    def line_count(self) -> int:
        return self.end_line - self.start_line + 1

    @property
    def is_candidate(self) -> bool:
        return self.word_count >= MIN_CANDIDATE_WORDS

    @property
    def lines_field(self) -> str:
        return f"L{self.start_line}-L{self.end_line}"


def _parse_paragraphs(path: str) -> list[Paragraph]:
    """Split a markdown file into prose paragraphs (skipping fenced code)."""
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    paragraphs: list[Paragraph] = []
    in_code = False
    buf: list[str] = []
    buf_start = 0

    def flush(end_line: int) -> None:
        if not buf:
            return
        body = "\n".join(buf).strip()
        if body:
            paragraphs.append(Paragraph(
                file=path, start_line=buf_start, end_line=end_line,
                text=body, word_count=len(body.split()),
            ))
        buf.clear()

    for idx, raw in enumerate(lines, start=1):
        if _CODE_FENCE.match(raw):
            flush(idx - 1)
            in_code = not in_code
            continue
        if in_code:
            continue
        if raw.strip() == "":
            flush(idx - 1)
            continue
        if _LIST_MARKER.match(raw):
            # Flush only when buf already has >= MIN_CANDIDATE_WORDS words so
            # short item runs coalesce rather than spawn sub-floor fragments.
            if buf and len(" ".join(buf).split()) >= MIN_CANDIDATE_WORDS:
                flush(idx - 1)
                buf_start = idx
            elif not buf:
                buf_start = idx
        elif not buf:
            buf_start = idx
        buf.append(raw)
    flush(len(lines))
    return paragraphs


def _expand_corpus(paths: list[str], corpus_dir: str | None) -> list[str]:
    """Append every ``*.md`` under ``corpus_dir`` to ``paths`` (deduped, sorted)."""
    out = list(paths)
    if corpus_dir is None:
        return out
    base = Path(corpus_dir)
    if not base.is_dir():
        raise ValueError(f"corpus_dir not a directory: {corpus_dir}")
    for md in sorted(base.rglob("*.md")):
        spath = str(md)
        if spath not in out:
            out.append(spath)
    return out


def _call_llm(para_a: str, para_b: str) -> dict[str, Any]:
    """Metrics-only stub same-meaning judge (no LLM available path).

    Always returns ``is_paraphrased=False`` — G1 has no literal heuristic
    available without a real LLM, so the safest fallback is zero findings.
    test_g1_logic.py keeps this entry point patchable via
    ``unittest.mock.patch.object(g1, "_call_llm", ...)``; Task 4b adds a
    parallel ``llm_dispatch`` keyword for real LLM wiring.
    """
    return {"is_paraphrased": False, "confidence": "low"}


def _llm_judge(
    para_a: Paragraph,
    para_b: Paragraph,
    dispatch: Callable[[dict], dict],
) -> dict[str, Any]:
    """Call ``dispatch`` with a structured record and normalise its reply.

    Defensive against malformed replies: missing fields default to a
    negative judgment so the validator drops it cleanly.
    """
    record = {
        "paragraph_a": {
            "file": para_a.file, "lines": para_a.lines_field, "text": para_a.text,
        },
        "paragraph_b": {
            "file": para_b.file, "lines": para_b.lines_field, "text": para_b.text,
        },
    }
    try:
        reply = dispatch(record)
    except Exception as exc:  # pragma: no cover - defensive
        print(f"g1: llm_dispatch raised {exc!r}, skipping pair", file=sys.stderr)
        return {"is_paraphrased": False, "confidence": "low"}
    if not isinstance(reply, dict):
        return {"is_paraphrased": False, "confidence": "low", "_malformed": True}
    return reply


def _validate_evidence(
    judgment: dict,
    para_a: Paragraph,
    para_b: Paragraph,
    totals: dict[str, int],
) -> tuple[bool, str]:
    """Validate line-range + (optional) substring of an LLM judgment."""
    for label, para in (("a", para_a), ("b", para_b)):
        rng = judgment.get(f"evidence_{label}", "")
        m = _LINE_RANGE_RE.match(rng) if isinstance(rng, str) else None
        if not m:
            return False, f"malformed evidence_{label}: {rng!r}"
        start, end = int(m.group(1)), int(m.group(2))
        file_total = totals.get(para.file, 0)
        if start < 1 or end > file_total or start > end:
            return (
                False,
                f"out-of-bounds evidence_{label} L{start}-L{end} "
                f"(file {para.file} has {file_total} lines)",
            )
        quote = judgment.get(f"evidence_quote_{label}")
        if quote and isinstance(quote, str) and quote.strip():
            if quote.strip() not in para.text:
                return False, (
                    f"evidence_quote_{label} not a substring of "
                    f"{para.file}:{para.lines_field}"
                )
    return True, ""


class _DSU:
    """Disjoint-set union — groups candidate paragraphs by positive match."""

    def __init__(self) -> None:
        self.parent: dict[int, int] = {}

    def add(self, x: int) -> None:
        self.parent.setdefault(x, x)

    def find(self, x: int) -> int:
        self.add(x)
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a: int, b: int) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[ra] = rb


def _severity_for(distinct_skill_count: int, max_shared_lines: int) -> str:
    if distinct_skill_count >= 3:
        return "HIGH"
    if distinct_skill_count == 2 and max_shared_lines >= MED_LINE_THRESHOLD:
        return "MED"
    return "LOW"


def _confidence_for(distinct_skill_count: int) -> str:
    return "high" if distinct_skill_count >= 3 else "medium"  # rubric L70-71


def _fmt_lines(p: Paragraph) -> str:
    return p.lines_field


def _evidence_block(paras: list[Paragraph]) -> str:
    return "\n".join(
        f"{p.file} {_fmt_lines(p)}:\n  {p.text.splitlines()[0] if p.text else ''}"
        for p in paras
    )


def _build_finding(
    idx: int,
    paras: list[Paragraph],
    disposition: str | None = None,
) -> dict[str, Any]:
    distinct_count = len({p.file for p in paras})
    max_shared_lines = max(p.line_count for p in paras)
    intra_file = distinct_count == 1
    finding: dict[str, Any] = {
        "id": f"g1-{idx:03d}",
        "axis": "G1",
        "severity": _severity_for(distinct_count, max_shared_lines),
        "confidence": _confidence_for(distinct_count),
        "title": (f"{distinct_count} skill(s) share a same-meaning paragraph "
                  f"({max_shared_lines} lines max)"),
        "summary": (f"LLM judged paragraphs across {distinct_count} skill "
                    "file(s) as paraphrased same-meaning content. Recommend "
                    "extracting to _shared/ or single-owner + cross-link."),
        "locations": [{"file": p.file, "lines": _fmt_lines(p)} for p in paras],
        "evidence_quote": _evidence_block(paras),
        "numeric_basis": None,
        "suggested_action": ("Extract the shared paragraph to _shared/<topic>.md "
                             "and replace each call site with a cross-link."),
        "requires_human": True,
    }
    if intra_file and disposition is not None:
        finding["disposition"] = disposition
    return finding


def detect(
    paths: list[str],
    no_llm: bool = False,
    *,
    corpus_dir: str | None = None,
    llm_dispatch: Optional[Callable[[dict], dict]] = None,
    _drop_limit: int = 3,
) -> list[dict]:
    """Run G1 detection (LLM-driven, with metrics-only fallback).

    G1 is now file-agnostic: it judges paragraph pairs both within a single
    file (intra-file) and across files (cross-skill).  Intra-file findings
    carry a ``disposition`` field (``merge`` or ``divergent-hazard``).
    A deterministic token-Jaccard prefilter (threshold ``MIN_PAIR_JACCARD``)
    prunes obvious non-duplicates before the LLM call.

    Args:
        paths: SKILL.md / references/*.md paths.  A single path is allowed
            (self-compare) provided the file contains >= 2 candidate
            paragraphs.  Pass ``corpus_dir`` to add more files for
            cross-skill comparison.
        no_llm: when True, skip LLM phase and return ``[]`` (metrics-only).
        corpus_dir: optional dir; every ``*.md`` recursively appended.
        llm_dispatch: optional callable ``(record) -> dict`` for real LLM.
            When ``None`` and ``no_llm`` is False, emits a stderr warning and
            falls back to ``_call_llm`` (which returns is_paraphrased=False).
        _drop_limit: anti-hallucination cap; raises RuntimeError when reached.

    Raises:
        G1InsufficientContentError: < 2 candidate paragraphs after expansion
            (advisory N/A; a ValueError subclass).
        ValueError: ``corpus_dir`` not a directory (genuine bad-arg error).
        RuntimeError: >= ``_drop_limit`` out-of-bounds evidence drops.
    """
    all_paths = _expand_corpus(paths, corpus_dir)

    file_paragraphs = {p: _parse_paragraphs(p) for p in all_paths}
    file_totals = {
        p: len(Path(p).read_text(encoding="utf-8").splitlines()) for p in all_paths
    }
    candidates: list[Paragraph] = [
        para for p in all_paths for para in file_paragraphs[p]
        if para.is_candidate
    ]
    if len(candidates) < 2:
        raise G1InsufficientContentError(
            f"G1 needs >= 2 candidate paragraphs (>= {MIN_CANDIDATE_WORDS} words "
            f"each) after corpus expansion; got {len(candidates)} across "
            f"{len(all_paths)} path(s): {all_paths!r}"
        )

    if no_llm:
        # §6 case-3: cross-skill semantic dup is an OPEN concept — no deterministic
        # heuristic (Jaccard included) can confirm same-meaning without an LLM.
        # Returning bare [] is fail-silent (caller cannot distinguish "no dups found"
        # from "axis not run"). Return an explicit N/A advisory so callers know the
        # axis was intentionally skipped (fail-loud).
        return [{
            "id": "g1-na",
            "axis": "G1",
            "severity": "NOT_APPLICABLE",
            "not_applicable": True,
            "confidence": "N/A",
            "title": "G1 cross-skill dup: N/A under --no-llm (open concept needs LLM)",
            "summary": (
                "cross-skill dup needs LLM semantic judgment; not run under --no-llm. "
                f"Token-Jaccard prefilter found {len(candidates)} candidate paragraph(s) "
                f"across {len(all_paths)} file(s) — semantic judgment requires an LLM. "
                "Re-run without --no-llm to get actionable results."
            ),
            "locations": [],
            "evidence_quote": "",
            "numeric_basis": None,
            "suggested_action": "Re-run without --no-llm to enable G1 cross-skill duplication detection.",
            "requires_human": False,
        }]

    if llm_dispatch is None:
        print(
            "g1: no llm_dispatch provided, falling back to metrics-only "
            "(zero findings unless _call_llm is patched)",
            file=sys.stderr,
        )

    dsu = _DSU()
    for i in range(len(candidates)):
        dsu.add(i)

    # pair_dispositions: maps DSU-group key to intra-file disposition.
    # Only the last positive intra-file pair to merge into a group sets it;
    # cross-file groups leave the key absent.
    pair_dispositions: dict[tuple[int, int], str] = {}

    drop_count = 0
    for i in range(len(candidates)):
        for j in range(i + 1, len(candidates)):
            a, b = candidates[i], candidates[j]

            # Jaccard prefilter — drop obvious non-dups before LLM call.
            if _token_jaccard(a.text, b.text) < MIN_PAIR_JACCARD:
                continue

            if llm_dispatch is not None:
                judgment = _llm_judge(a, b, llm_dispatch)
                if not judgment.get("is_paraphrased"):
                    continue
                ok, reason = _validate_evidence(judgment, a, b, file_totals)
                if not ok:
                    drop_count += 1
                    print(
                        f"g1: evidence validation failed ({reason}); "
                        f"dropped pair {a.file}:{a.lines_field} <-> "
                        f"{b.file}:{b.lines_field}",
                        file=sys.stderr,
                    )
                    if drop_count >= _drop_limit:
                        raise RuntimeError(
                            f"g1: >= {_drop_limit} evidence_quote out-of-bounds "
                            "in single run, result untrustworthy "
                            "(audit.py should exit 1)"
                        )
                    continue
                # Record disposition for same-file pairs.
                if a.file == b.file:
                    cdv = judgment.get("carries_divergent_value")
                    if cdv is True:
                        disp = "divergent-hazard"
                    elif cdv is False:
                        disp = "merge"
                    else:
                        # Missing or uncertain → bias to hazard (default-conservative).
                        disp = "divergent-hazard"
                    pair_dispositions[(i, j)] = disp
                dsu.union(i, j)
            else:
                if _call_llm(a.text, b.text).get("is_paraphrased"):
                    dsu.union(i, j)

    groups: dict[int, list[int]] = {}
    for idx in range(len(candidates)):
        groups.setdefault(dsu.find(idx), []).append(idx)

    findings: list[dict] = []
    next_id = 1
    for members in groups.values():
        if len(members) < 2:
            continue
        paras = [candidates[i] for i in members]
        distinct_files = {p.file for p in paras}
        intra_file = len(distinct_files) == 1

        # Compute disposition for intra-file groups.
        disposition: str | None = None
        if intra_file:
            # Collect dispositions from all member pairs in this group.
            # Any divergent-hazard in the group dominates (conservative).
            group_set = set(members)
            disps = [
                disp for (pi, pj), disp in pair_dispositions.items()
                if pi in group_set and pj in group_set
            ]
            if not disps:
                # No LLM disposition recorded (e.g. _call_llm path) → hazard.
                disposition = "divergent-hazard"
            elif any(d == "divergent-hazard" for d in disps):
                disposition = "divergent-hazard"
            else:
                disposition = "merge"

        paras.sort(key=lambda p: (p.file, p.start_line))
        findings.append(_build_finding(next_id, paras, disposition=disposition))
        next_id += 1
    return findings


__all__ = ["detect", "Paragraph"]
