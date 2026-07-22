#!/usr/bin/env python3
"""merge-findings.py — apply-order + same-range merge planner for prose-guidelines.

Reads a **validated** findings YAML (the stdout of ``validate-findings.sh``)
and emits an ordered list of apply-units to **stdout as JSON**. Exit non-zero
only on the overlap-conflict case (G4(b)).

Pipeline (spec G4 / G7):

  (a) bottom-up order — apply units are sorted by start-line DESCENDING, so
      applying an earlier Edit never shifts the line numbers of a later one.
  (b) non-overlap assert (after grouping) — accepted findings sharing the
      *same* source range merge into one unit; two findings on *different but
      overlapping* ranges are a conflict -> non-zero exit.
  (c) same-range merge -> ONE apply unit. meta precedence is SENTENCE-LEVEL,
      not whole-paragraph (per G7): the meta finding deletes only its own
      sentence(s); a lexical/paragraph finding on the same range applies to
      the *remainder*; they conflict (meta wins outright for that sentence)
      only when both target the same sentence.
  (d) unique old_string — the text a finding replaces must match **uniquely**
      in the raw (un-normalized) target-file text, or the finding is skipped
      (reported on stderr; no best-effort fuzzy match).

Usage:
    python3 scripts/merge-findings.py <validated.yaml> [<target-file>]

If <target-file> is omitted, the YAML's top-level ``file:`` key (relative to
the repo root, i.e. two levels above scripts/) is used.

Exit codes:
    0  — units emitted (possibly with skipped/empty); no overlap conflict
    1  — overlapping-but-distinct ranges (G4(b) conflict)
    2  — bad input (file missing, malformed YAML)

Output (stdout, JSON):
    {
      "file": "<target path>",
      "units": [
        {
          "lines": "L<s>-L<e>",
          "start_line": <int>,        # 1-based; units sorted by this DESC
          "end_line": <int>,
          "old_string": "<raw range text matched verbatim in the file>",
          "new_string": "<merged replacement>",
          "sources": ["meta", "lexical", ...]   # finding_class of each merged finding
        },
        ...
      ],
      "skipped": [
        {"lines": "...", "reason": "old_string not unique in raw file text"},
        ...
      ]
    }

The apply loop (task 3 / SKILL.md) iterates ``units`` top-to-bottom (already
DESC) and runs one Edit(old_string, new_string) per unit against the raw file.

Sentence splitter (deterministic, stdlib-only): a sentence ends at one of
``. ! ?`` followed by whitespace or end-of-string, OR at a CJK terminator
``。 ！ ？`` (optionally followed by whitespace). The terminator stays attached
to the sentence it ends. No abbreviation/decimal heuristics — deterministic by
design (a number like ``3.5`` keeps its dot because the dot is not followed by
whitespace).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("merge-findings: PyYAML required (pip install pyyaml)\n")
    sys.exit(2)

RANGE_RE = re.compile(r"^L(\d+)-L(\d+)$")

# Sentence boundary: latin terminator + (whitespace | EOS), or CJK terminator
# (optionally trailing whitespace). Keep the terminator with the sentence.
_SENT_SPLIT = re.compile(r"(?<=[.!?])\s+|(?<=[。！？])\s*")


def split_sentences(text):
    """Deterministic sentence split. Returns a list of non-empty sentences with
    surrounding whitespace stripped (for set comparison); empty fragments are
    dropped."""
    parts = _SENT_SPLIT.split(text)
    return [p.strip() for p in parts if p and p.strip()]


def _parse_range(rng):
    m = RANGE_RE.match(str(rng))
    if not m:
        return None
    s, e = int(m.group(1)), int(m.group(2))
    return s, e


#: Unique sentinel returned as the new_string when a span carries >=2 non-meta
#: findings — an ambiguous compose the planner refuses to guess (see
#: merge_same_range_group). A bare ``object()`` (not a str) so the identity
#: check in main() can never collide with a legitimate rewritten_text value.
CONFLICT_MULTI_NONMETA = object()

#: Human-readable reason recorded in skipped[] for the multi-non-meta conflict.
CONFLICT_MULTI_NONMETA_REASON = "multiple non-meta findings on one span — ambiguous compose"


def merge_same_range_group(group, raw_range_text):
    """Collapse a list of findings sharing one source range into a single
    (new_string, sources) pair using sentence-level meta precedence +
    **whole-span replace** for the (single) non-meta finding.

    ``raw_range_text`` is the verbatim file text of the range (the old_string).

    Meta findings delete only their own sentence(s); the non-meta finding then
    replaces the WHOLE surviving (post-meta-deletion) span with its
    ``rewritten_text`` — NOT per-sentence passthrough, so a finding whose
    ``evidence_quote`` covers only a subset of the paragraph cannot leave the
    uncited remainder appended.

    Conflict signal: a span with **>=2** non-meta findings is an ambiguous
    compose (sequential apply would clobber, since finding-2's evidence_quote
    references pre-finding-1 text). Such a group returns
    ``(CONFLICT_MULTI_NONMETA, sources)`` — where ``CONFLICT_MULTI_NONMETA`` is
    a unique sentinel object — so the caller skips the unit (via an identity
    check) rather than guessing a merge order.
    """
    sentences = split_sentences(raw_range_text)
    sources = [f.get("finding_class") for f in group]

    metas = [f for f in group if f.get("finding_class") == "meta"]
    others = [f for f in group if f.get("finding_class") != "meta"]

    # >=2 non-meta findings on one span: refuse to guess a merge order.
    if len(others) >= 2:
        return CONFLICT_MULTI_NONMETA, sources

    # Sentences the meta finding deletes = those present in the original range
    # but absent from the meta's rewritten_text (G7: meta rewrite = paragraph
    # minus its meta sentence(s)).
    meta_deleted = set()
    for f in metas:
        rw = f.get("rewritten_text") or ""
        kept = set(split_sentences(rw))
        for sent in sentences:
            if sent not in kept:
                meta_deleted.add(sent)

    # Start from the surviving (non-meta-deleted) sentences, in original order.
    surviving = [s for s in sentences if s not in meta_deleted]

    if others:
        # Exactly one non-meta finding: whole-span replace of the surviving
        # (post-meta-deletion) span. Its rewritten_text IS the new content, but
        # meta precedence still wins for any sentence the meta deleted — so we
        # drop any meta-deleted sentence the non-meta rewrite re-introduces
        # (e.g. a lexical rewrite that echoes the whole paragraph). Operating on
        # the surviving span this way never re-injects a meta-deleted sentence.
        # Empty rewritten_text => pure deletion (collapse to "").
        rw_text = others[0].get("rewritten_text") or ""
        if meta_deleted:
            kept = [s for s in split_sentences(rw_text) if s not in meta_deleted]
            # CASE-A content-loss guard: if subtracting the meta-deleted
            # sentences empties the non-meta rewrite entirely (e.g. the rewrite
            # echoed ONLY meta-deleted sentences) but there were surviving
            # non-meta sentences to preserve, do NOT annihilate them. Prefer the
            # meta-surviving span over emitting "" — meta deletes its own
            # sentences, the remainder survives. (An intentional empty rewrite
            # collapses to "" via the empty-rewrite branch below, not here.)
            if not kept and surviving:
                return " ".join(surviving), sources
            return " ".join(kept), sources
        return rw_text.strip(), sources

    # No non-meta finding: emit only the meta-surviving sentences.
    new_string = " ".join(surviving)
    return new_string, sources


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: merge-findings.py <validated.yaml> [<target-file>]\n")
        return 2
    yaml_path = Path(argv[1])
    if not yaml_path.is_file():
        sys.stderr.write(f"merge-findings: yaml not found: {yaml_path}\n")
        return 2
    try:
        doc = yaml.safe_load(yaml_path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        sys.stderr.write(f"merge-findings: malformed YAML: {exc}\n")
        return 2

    findings = doc.get("findings") or []

    # Resolve target file. CLI arg wins; else YAML `file:` relative to repo root
    # (scripts/ -> prose-guidelines/ -> repo root = two parents up from this file).
    if len(argv) >= 3:
        target = Path(argv[2])
    else:
        rel = doc.get("file")
        if not rel:
            sys.stderr.write("merge-findings: no target file (pass arg or set `file:`)\n")
            return 2
        repo_root = Path(__file__).resolve().parents[2]
        target = repo_root / rel
    if not target.is_file():
        sys.stderr.write(f"merge-findings: target file not found: {target}\n")
        return 2
    file_text = target.read_text(encoding="utf-8")
    file_lines = file_text.splitlines()

    # --- group by identical source range -------------------------------------
    groups = {}  # (s,e) -> list[finding]
    order = []
    for i, f in enumerate(findings):
        f = f or {}
        pr = _parse_range(f.get("lines"))
        if pr is None:
            sys.stderr.write(f"merge-findings: skip #{i} malformed lines={f.get('lines')!r}\n")
            continue
        if pr not in groups:
            groups[pr] = []
            order.append(pr)
        groups[pr].append(f)

    # --- (b) pairwise non-overlap assert across DISTINCT ranges --------------
    ranges = sorted(groups.keys())
    for a in range(len(ranges)):
        for b in range(a + 1, len(ranges)):
            (s1, e1), (s2, e2) = ranges[a], ranges[b]
            if s1 <= e2 and s2 <= e1:  # intervals overlap, and they are distinct
                sys.stderr.write(
                    f"merge-findings: CONFLICT overlapping distinct ranges "
                    f"L{s1}-L{e1} and L{s2}-L{e2}\n"
                )
                return 1

    # --- (c) same-range merge + (d) unique old_string ------------------------
    units = []
    skipped = []
    for (s, e) in order:
        group = groups[(s, e)]
        raw_range_text = "\n".join(file_lines[s - 1:e])
        # (d) old_string must match uniquely in the raw file text.
        if file_text.count(raw_range_text) != 1:
            skipped.append({
                "lines": f"L{s}-L{e}",
                "reason": "old_string not unique in raw file text",
            })
            sys.stderr.write(
                f"merge-findings: skip L{s}-L{e} — old_string not unique in raw file text\n"
            )
            continue
        new_string, sources = merge_same_range_group(group, raw_range_text)
        if new_string is CONFLICT_MULTI_NONMETA:
            skipped.append({
                "lines": f"L{s}-L{e}",
                "reason": CONFLICT_MULTI_NONMETA_REASON,
            })
            sys.stderr.write(
                f"merge-findings: skip L{s}-L{e} — {CONFLICT_MULTI_NONMETA_REASON}\n"
            )
            continue
        units.append({
            "lines": f"L{s}-L{e}",
            "start_line": s,
            "end_line": e,
            "old_string": raw_range_text,
            "new_string": new_string,
            "sources": sources,
        })

    # --- (a) bottom-up: sort by start-line DESCENDING ------------------------
    units.sort(key=lambda u: u["start_line"], reverse=True)

    out = {"file": str(target), "units": units, "skipped": skipped}
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
