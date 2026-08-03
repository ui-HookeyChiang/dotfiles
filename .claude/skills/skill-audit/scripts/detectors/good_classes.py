"""GC: SKILL.md good-class conformance detector.

Public API: ``detect(paths, *, no_llm=False, llm_dispatch=None, corpus_dir=None)``
    Returns list[dict] of advisory findings per ``references/finding-schema.md``.

The six good-classes are defined by ``skill-guidelines``:
triggers/routing, contracts, live-mechanism instructions,
preconditions/caveats, disambiguation, and pointers.

This detector is intentionally conservative. It classifies top-level SKILL.md
sections by strong heading/body cues and flags only sections matching none of
the six classes. The finding is advisory LOW severity; a writer still owns the
final placement decision.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable


AXIS = "GC"
_HEADING_RE = re.compile(r"^(#{2,3})\s+(.+?)\s*$")
_FENCE_RE = re.compile(r"^\s*```")

_CLASS_CUES: dict[str, tuple[str, ...]] = {
    "triggers/routing": (
        "when to use", "trigger", "route", "routing", "intent", "use when",
    ),
    "contracts": (
        "contract", "input", "output", "exit code", "side effect",
        "invariant", "ordering", "must emit", "returns",
    ),
    "live-mechanism instructions": (
        "run", "invoke", "dispatch", "execute", "command", "script",
        "step", "phase", "gate", "workflow",
    ),
    "preconditions/caveats": (
        "precondition", "caveat", "guard", "hard stop", "stop", "never",
        "always", "must not", "only if", "skip", "fallback",
    ),
    "disambiguation": (
        "not this", "vs", "versus", "choose", "instead", "use x",
    ),
    "pointers": (
        "see also", "references/", "scripts/", "docs/", ".md", ".sh",
        ".py", "see `", "ref:",
    ),
}


@dataclass(frozen=True)
class Section:
    title: str
    start_line: int
    end_line: int
    lines: list[str]

    @property
    def text(self) -> str:
        return "\n".join(self.lines)


def _strip_frontmatter(lines: list[str]) -> tuple[list[str], int]:
    if not lines or lines[0].strip() != "---":
        return lines, 0
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            return lines[idx + 1:], idx + 1
    return lines, 0


def _parse_sections(path: Path) -> list[Section]:
    lines = path.read_text(encoding="utf-8").splitlines()
    body, offset = _strip_frontmatter(lines)
    sections: list[Section] = []
    current_title = ""
    current_start = 1 + offset
    current_lines: list[str] = []
    in_fence = False

    def flush(end_line: int) -> None:
        nonlocal current_title, current_start, current_lines
        if current_title and any(ln.strip() for ln in current_lines):
            sections.append(Section(
                title=current_title,
                start_line=current_start,
                end_line=end_line,
                lines=current_lines[:],
            ))
        current_lines = []

    for rel_idx, line in enumerate(body, start=1 + offset):
        if _FENCE_RE.match(line):
            in_fence = not in_fence
        heading = _HEADING_RE.match(line) if not in_fence else None
        if heading and len(heading.group(1)) == 2:
            flush(rel_idx - 1)
            current_title = heading.group(2).strip()
            current_start = rel_idx
            current_lines = [line]
        elif current_title:
            current_lines.append(line)
    flush(len(lines))
    return sections


def _matched_classes(section: Section) -> set[str]:
    blob = f"{section.title}\n{section.text}".lower()
    matched = {
        class_name
        for class_name, cues in _CLASS_CUES.items()
        if any(cue in blob for cue in cues)
    }
    if "[" in section.text and "](" in section.text:
        matched.add("pointers")
    if "```" in section.text:
        matched.add("live-mechanism instructions")
    return matched


def _is_exempt(section: Section) -> bool:
    title = section.title.strip().lower()
    if title in {"overview", "summary"}:
        # Short intro sections are often just the skill's one-sentence contract.
        words = re.findall(r"[A-Za-z0-9_]+", section.text)
        return len(words) <= 80
    return False


def _build_finding(idx: int, path: Path, section: Section) -> dict[str, Any]:
    return {
        "id": f"gc-{idx:03d}",
        "axis": AXIS,
        "severity": "LOW",
        "confidence": "medium",
        "title": f"Section '{section.title}' does not match a SKILL.md good-class",
        "summary": (
            "The section lacks strong cues for the six skill-guidelines "
            "good-classes: triggers/routing, contracts, live mechanism, "
            "preconditions/caveats, disambiguation, or pointers."
        ),
        "locations": [{
            "file": str(path),
            "lines": f"L{section.start_line}-L{section.end_line}",
        }],
        "evidence_quote": section.lines[0].strip() if section.lines else section.title,
        "numeric_basis": {
            "matched_good_classes": [],
            "section_lines": section.end_line - section.start_line + 1,
        },
        "suggested_action": (
            "Rewrite the section as one of the six good-classes or move the "
            "background/narrative material to references/."
        ),
        "requires_human": True,
    }


def detect(
    paths: Iterable[str],
    *,
    no_llm: bool = False,
    llm_dispatch: Callable[[dict], dict] | None = None,
    corpus_dir: str | None = None,
    **_kwargs: Any,
) -> list[dict]:
    """Run section-level good-class conformance detection.

    ``no_llm``, ``llm_dispatch``, and ``corpus_dir`` are accepted for semantic
    detector interface consistency. This implementation is deterministic and
    advisory; the LLM leg can still review emitted candidates.
    """
    findings: list[dict] = []
    next_id = 1
    for raw_path in paths:
        path = Path(raw_path)
        if path.name != "SKILL.md" or not path.is_file():
            continue
        for section in _parse_sections(path):
            if _is_exempt(section):
                continue
            if _matched_classes(section):
                continue
            findings.append(_build_finding(next_id, path, section))
            next_id += 1
    return findings


__all__ = ["detect", "Section"]
