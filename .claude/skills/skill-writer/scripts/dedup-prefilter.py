#!/usr/bin/env python3
"""Deterministic pre-pass for skill-writer Phase 1 dedup sweep.

Narrows the sweep's LLM step: computes the parts that are mechanical
(invoke-cycle graph, lexical overlap ranking, keyword + _shared presence) so
the Explore agent runs only on a high-overlap shortlist — or not at all when
nothing scores close and no cycle exists.

Output is a JSON brief on stdout the main agent reads to decide:
  - candidate in a cycle      -> CIRCULAR (warn; the candidate's own edge forms a loop)
  - top lexical score >= --threshold -> LLM confirms the shortlist (semantic dup)
  - else                      -> NO OVERLAP, the LLM sweep may be skipped

CIRCULAR is scoped to THIS request: it fires only when the candidate skill
(`--self`, or a new skill whose declared `--invokes` close a loop) participates
in a cycle. Pre-existing cycles between OTHER skills are reported separately as
`preexisting_cycles` (advisory repo-hygiene note) and do NOT set the verdict —
they are not this request's concern.

The LLM still owns the semantic judgment (is this a true paraphrase / partial
overlap). This pass only removes the obviously-unrelated bulk and does the
cycle graph exactly (a thing the LLM does unreliably across many files).

Usage:
  dedup-prefilter.py --request "<skill description>" [--repo <dir>]
                     [--self <skill-name>] [--invokes a,b] [--threshold 0.08] [--top 5]

  --request   the skill description / change request to compare against.
  --self      the skill being modified (excluded from its own overlap match;
              CIRCULAR fires if it sits in a cycle).
  --invokes   comma-list of skills the NEW skill will invoke (create mode);
              CIRCULAR fires if any closes a loop back to the candidate.
  --repo      repo root holding the skill dirs (default: cwd).
  --threshold lexical-overlap floor; top score below it => NO OVERLAP.
  --top       shortlist size handed to the LLM.

Exit: 0 always (a brief is advisory input, never a gate). stderr carries
parse warnings only.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

_TOKEN_RE = re.compile(r"[a-z0-9]+")
_INVOKE_RE = re.compile(r"\bSkill\s+([a-z][a-z0-9-]+)")
_DESC_RE = re.compile(r"^description:\s*(.+)", re.MULTILINE)
# stop-words: generic skill-prose that would inflate every pairwise overlap.
_STOP = frozenset((
    "the", "a", "an", "to", "of", "for", "and", "or", "in", "on", "is", "use",
    "when", "this", "that", "with", "skill", "skills", "via", "from", "by",
    "it", "as", "be", "are", "not", "user", "users", "any", "run", "runs",
))


def _tokens(text: str) -> set[str]:
    return {t for t in _TOKEN_RE.findall(text.lower()) if t not in _STOP}


def _jaccard(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def _skill_dirs(repo: Path) -> list[str]:
    return sorted(
        d.name for d in repo.iterdir()
        if d.is_dir() and (d / "SKILL.md").is_file()
    )


def _read_skill_text(repo: Path, name: str) -> str:
    """SKILL.md body + any references/*.md, for edge extraction."""
    parts = []
    sk = repo / name / "SKILL.md"
    parts.append(sk.read_text(encoding="utf-8", errors="ignore"))
    refdir = repo / name / "references"
    if refdir.is_dir():
        for f in sorted(refdir.glob("*.md")):
            parts.append(f.read_text(encoding="utf-8", errors="ignore"))
    return "\n".join(parts)


def _description(repo: Path, name: str) -> str:
    text = (repo / name / "SKILL.md").read_text(encoding="utf-8", errors="ignore")
    m = _DESC_RE.search(text)
    # description may be a `|` block; grab the first ~600 chars of body either way.
    if m:
        return m.group(1).strip()[:600]
    return ""


def _build_edges(repo: Path, names: list[str]) -> dict[str, set[str]]:
    nameset = set(names)
    edges: dict[str, set[str]] = {}
    for n in names:
        invoked = set(_INVOKE_RE.findall(_read_skill_text(repo, n))) & nameset
        invoked.discard(n)
        edges[n] = invoked
    return edges


def _find_cycles(edges: dict[str, set[str]]) -> list[list[str]]:
    """DFS cycle detection; returns each distinct cycle as a node path."""
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n: WHITE for n in edges}
    stack: list[str] = []
    cycles: list[list[str]] = []
    seen_keys: set[frozenset] = set()

    def dfs(n: str) -> None:
        color[n] = GRAY
        stack.append(n)
        for m in edges.get(n, ()):
            if color.get(m) == GRAY:
                i = stack.index(m)
                cyc = stack[i:] + [m]
                key = frozenset(cyc)
                if key not in seen_keys:
                    seen_keys.add(key)
                    cycles.append(cyc)
            elif color.get(m) == WHITE:
                dfs(m)
        stack.pop()
        color[n] = BLACK

    for n in edges:
        if color[n] == WHITE:
            dfs(n)
    return cycles


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True, help="skill description / change request")
    ap.add_argument("--self", dest="self_name", default=None,
                    help="skill under modification (excluded from overlap match)")
    ap.add_argument("--invokes", default="",
                    help="comma-list of skills a NEW skill will invoke (create mode)")
    ap.add_argument("--repo", default=".", help="repo root (default cwd)")
    ap.add_argument("--threshold", type=float, default=0.08,
                    help="lexical floor; top score below => NO OVERLAP")
    ap.add_argument("--top", type=int, default=5, help="shortlist size")
    args = ap.parse_args(argv)

    repo = Path(args.repo).resolve()
    names = _skill_dirs(repo)
    if not names:
        print(json.dumps({"error": f"no skills under {repo}"}))
        return 0

    req = _tokens(args.request)
    scored = []
    for n in names:
        if n == args.self_name:
            continue
        j = _jaccard(req, _tokens(_description(repo, n)))
        scored.append((round(j, 3), n))
    scored.sort(reverse=True)
    shortlist = [{"skill": n, "lexical": j} for j, n in scored[: args.top] if j > 0]

    edges = _build_edges(repo, names)
    # create-mode: a new skill named --self that will invoke --invokes targets.
    if args.self_name and args.self_name not in edges:
        edges[args.self_name] = set()
    if args.invokes and args.self_name:
        edges[args.self_name] |= {
            s.strip() for s in args.invokes.split(",") if s.strip() in edges
        }

    all_cycles = _find_cycles(edges)
    candidate = args.self_name
    candidate_cycles = [c for c in all_cycles if candidate and candidate in c]
    preexisting_cycles = [c for c in all_cycles if c not in candidate_cycles]

    top = scored[0][0] if scored else 0.0
    if candidate_cycles:
        recommendation = "CIRCULAR"
    elif top >= args.threshold:
        recommendation = "LLM_CONFIRM_SHORTLIST"
    else:
        recommendation = "NO_OVERLAP_LLM_SKIPPABLE"

    print(json.dumps({
        "recommendation": recommendation,
        "top_lexical": top,
        "threshold": args.threshold,
        "shortlist": shortlist,
        "candidate_cycles": candidate_cycles,
        "preexisting_cycles": preexisting_cycles,
        "note": (
            "Deterministic pre-pass. The LLM still judges true paraphrase/"
            "partial-overlap on the shortlist. CIRCULAR is scoped to the "
            "candidate (--self/--invokes) — a candidate cycle overrides even at "
            "low overlap. preexisting_cycles are an advisory repo-hygiene note, "
            "NOT this request's verdict. NO_OVERLAP_LLM_SKIPPABLE means the "
            "Explore sweep adds little — confirm and skip to Phase 2."
        ),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
