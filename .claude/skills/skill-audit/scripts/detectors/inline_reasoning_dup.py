"""IRD: Inline-reasoning-duplication detector.

Public API: ``detect(paths, *, no_llm=False, corpus_dir=None)``
    Returns list[dict] of findings per ``references/finding-schema.md``.

Triggers only when SKILL.md > 200 lines.

Detects: multi-step reasoning workflows (3+ sequential numbered/bulleted
steps) in the SKILL.md body that overlap with an existing skill's
description keywords.

Output: advisory LOW severity finding — "Stage X's inline reasoning
(~N lines) overlaps with Skill Y's description. Consider delegating
via 'Invoke Skill Y' + gate condition."

Overlap detection is simple and deterministic: substring matching of
skill directory names and key verbs extracted from skill descriptions.
No LLM required.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Iterable

# ── Thresholds ───────────────────────────────────────────────────────────────

MIN_SKILL_LINES = 200  # only trigger for SKILL.md > 200 lines
MIN_STEP_COUNT = 3     # minimum sequential steps to form a reasoning block

# ── Regex patterns ───────────────────────────────────────────────────────────

# Numbered list items: "1.", "2.", "3." etc. (with optional leading whitespace)
_NUMBERED_RE = re.compile(r"^\s*(\d+)\.\s+\S")
# Bulleted list items: "- " (with optional leading whitespace)
_BULLET_RE = re.compile(r"^\s*[-]\s+\S")
# Heading detection (to stop blocks at headings)
_HEADING_RE = re.compile(r"^#{1,6}\s+\S")
# Fence detection (to skip fenced code blocks)
_FENCE_RE = re.compile(r"^\s*```")
# YAML frontmatter description field
_DESC_FIELD_RE = re.compile(r"^description:\s*(.+)", re.IGNORECASE)
# XML-style description tags (used in skill registry)
_DESC_XML_OPEN_RE = re.compile(r"<description>")
_DESC_XML_CLOSE_RE = re.compile(r"</description>")

# Common stopwords to exclude from keyword extraction
_STOPWORDS = frozenset({
    "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did", "will", "would", "shall",
    "should", "may", "might", "must", "can", "could", "to", "of", "in",
    "for", "on", "with", "at", "by", "from", "as", "into", "through",
    "during", "before", "after", "above", "below", "between", "out",
    "off", "over", "under", "again", "further", "then", "once", "here",
    "there", "when", "where", "why", "how", "all", "both", "each",
    "every", "other", "some", "such", "no", "nor", "not", "only", "own",
    "same", "so", "than", "too", "very", "just", "because", "but", "and",
    "or", "if", "while", "that", "this", "these", "those", "it", "its",
    "i", "me", "my", "we", "our", "you", "your", "he", "him", "his",
    "she", "her", "they", "them", "their", "what", "which", "who",
    "whom", "use", "using", "used", "also", "any", "about", "up",
    "down", "more", "most", "less", "least", "many", "much", "few",
    "see", "e.g", "etc", "via", "per", "vs", "ie",
})

# Domain-specific stopwords: so common in this repo they carry no signal
_DOMAIN_STOPWORDS = frozenset({
    "build", "deploy", "device", "firmware", "test", "verify", "run",
    "pass", "check", "create", "update", "merge", "skill", "ubiquiti",
    "install", "config", "setup", "file", "script", "agent", "step",
    "phase", "stage", "output", "input", "result", "error", "log",
    "command", "branch", "commit", "push", "pull", "review", "pr",
    "use", "add", "set", "get", "make", "start", "stop", "work",
    "need", "also", "note", "see", "new", "first", "last", "each",
    "repo", "path", "name", "type", "data", "version", "spec",
    "product", "target", "source", "package", "dir", "read", "write",
    "load", "save", "list", "report", "status", "mode", "option",
    "task", "action", "change", "entry", "line", "block", "git",
})


# ── Data structures ──────────────────────────────────────────────────────────

class _ReasoningBlock:
    """A contiguous multi-step reasoning block found in a SKILL.md."""

    __slots__ = ("start_line", "end_line", "lines", "block_type")

    def __init__(
        self,
        start_line: int,
        end_line: int,
        lines: list[str],
        block_type: str,
    ) -> None:
        self.start_line = start_line   # 1-indexed
        self.end_line = end_line       # 1-indexed, inclusive
        self.lines = lines
        self.block_type = block_type   # "numbered" or "bulleted"

    @property
    def line_count(self) -> int:
        return self.end_line - self.start_line + 1

    def keywords(self) -> set[str]:
        """Extract non-stopword tokens from the block text."""
        text = " ".join(self.lines)
        tokens = re.findall(r"[a-zA-Z_][\w-]*", text.lower())
        return {
            t for t in tokens
            if t not in _STOPWORDS
            and t not in _DOMAIN_STOPWORDS
            and len(t) > 3
        }


class _SkillDesc:
    """A sibling skill's name and description keywords."""

    __slots__ = ("name", "description", "keywords")

    def __init__(self, name: str, description: str) -> None:
        self.name = name
        self.description = description
        tokens = re.findall(r"[a-zA-Z_][\w-]*", description.lower())
        self.keywords = {
            t for t in tokens
            if t not in _STOPWORDS
            and t not in _DOMAIN_STOPWORDS
            and len(t) > 3
        }


# ── Parsing helpers ──────────────────────────────────────────────────────────

def _parse_reasoning_blocks(text_lines: list[str]) -> list[_ReasoningBlock]:
    """Find multi-step reasoning blocks (3+ sequential steps).

    Scans for contiguous runs of numbered list items (1., 2., 3., ...)
    or bulleted list items (- ...) that are not inside fenced code blocks.
    A block ends at a heading, a fence, a blank line not followed by
    another list item of the same type, or EOF.
    """
    blocks: list[_ReasoningBlock] = []
    n = len(text_lines)
    i = 0
    in_fence = False

    while i < n:
        line = text_lines[i]

        # Track fenced code blocks — skip them entirely.
        if _FENCE_RE.match(line):
            in_fence = not in_fence
            i += 1
            continue
        if in_fence:
            i += 1
            continue

        # Try numbered list.
        m_num = _NUMBERED_RE.match(line)
        if m_num:
            block_start = i
            block_lines: list[str] = [line]
            step_count = 1
            j = i + 1
            while j < n:
                next_line = text_lines[j]
                if _FENCE_RE.match(next_line) or _HEADING_RE.match(next_line):
                    break
                if _NUMBERED_RE.match(next_line):
                    block_lines.append(next_line)
                    step_count += 1
                    j += 1
                elif next_line.strip() == "":
                    # Blank line: peek ahead for continuation.
                    if j + 1 < n and _NUMBERED_RE.match(text_lines[j + 1]):
                        block_lines.append(next_line)
                        j += 1
                    else:
                        break
                elif next_line.startswith("   ") or next_line.startswith("\t"):
                    # Continuation / indented content under a list item.
                    block_lines.append(next_line)
                    j += 1
                else:
                    break
            if step_count >= MIN_STEP_COUNT:
                blocks.append(_ReasoningBlock(
                    start_line=block_start + 1,
                    end_line=j,  # j is exclusive in 0-indexed, equals end+1
                    lines=block_lines,
                    block_type="numbered",
                ))
            i = j
            continue

        # Try bulleted list.
        if _BULLET_RE.match(line):
            block_start = i
            block_lines = [line]
            step_count = 1
            j = i + 1
            while j < n:
                next_line = text_lines[j]
                if _FENCE_RE.match(next_line) or _HEADING_RE.match(next_line):
                    break
                if _BULLET_RE.match(next_line):
                    block_lines.append(next_line)
                    step_count += 1
                    j += 1
                elif next_line.strip() == "":
                    if j + 1 < n and _BULLET_RE.match(text_lines[j + 1]):
                        block_lines.append(next_line)
                        j += 1
                    else:
                        break
                elif next_line.startswith("   ") or next_line.startswith("\t"):
                    block_lines.append(next_line)
                    j += 1
                else:
                    break
            if step_count >= MIN_STEP_COUNT:
                blocks.append(_ReasoningBlock(
                    start_line=block_start + 1,
                    end_line=j,
                    lines=block_lines,
                    block_type="bulleted",
                ))
            i = j
            continue

        i += 1

    return blocks


def _parse_skill_description(skill_md_path: Path) -> str | None:
    """Extract description from a SKILL.md file.

    Looks for:
      1. YAML frontmatter ``description:`` field
      2. ``<description>`` XML tags
      3. First non-heading, non-empty paragraph after frontmatter
    """
    try:
        text = skill_md_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None

    lines = text.splitlines()
    if not lines:
        return None

    # 1. YAML frontmatter
    if lines[0].strip() == "---":
        for k, ln in enumerate(lines[1:], start=1):
            if ln.strip() == "---":
                # End of frontmatter — scan the frontmatter for description.
                for fm_line in lines[1:k]:
                    m = _DESC_FIELD_RE.match(fm_line)
                    if m:
                        return m.group(1).strip()
                break

    # 2. XML-style <description> tags (used in some registries)
    full_text = text
    open_m = _DESC_XML_OPEN_RE.search(full_text)
    close_m = _DESC_XML_CLOSE_RE.search(full_text)
    if open_m and close_m and close_m.start() > open_m.end():
        return full_text[open_m.end():close_m.start()].strip()

    # 3. First non-heading, non-empty paragraph
    in_frontmatter = lines[0].strip() == "---"
    passed_frontmatter = not in_frontmatter
    for ln in lines:
        if in_frontmatter:
            if ln.strip() == "---" and passed_frontmatter:
                in_frontmatter = False
            elif ln.strip() == "---":
                passed_frontmatter = True
            continue
        if not ln.strip():
            continue
        if _HEADING_RE.match(ln):
            continue
        return ln.strip()

    return None


def _discover_sibling_skills(corpus_dir: str | None, target_path: str) -> list[_SkillDesc]:
    """Discover sibling skills' descriptions from corpus_dir.

    Looks for ``*/SKILL.md`` or ``SKILL.md`` files in corpus_dir,
    excluding the target file itself.
    """
    if not corpus_dir:
        # Try to infer from target path: go up to the skills root.
        target = Path(target_path).resolve()
        # If target is e.g. /path/to/skills/my-skill/SKILL.md,
        # corpus_dir would be /path/to/skills/
        if target.name == "SKILL.md":
            candidate = target.parent.parent
            if candidate.is_dir():
                corpus_dir = str(candidate)
            else:
                return []
        else:
            return []

    corpus = Path(corpus_dir)
    if not corpus.is_dir():
        return []

    target_resolved = Path(target_path).resolve()
    results: list[_SkillDesc] = []

    for skill_md in corpus.rglob("SKILL.md"):
        if skill_md.resolve() == target_resolved:
            continue
        # Only consider direct children: <corpus>/<skill-name>/SKILL.md
        if skill_md.parent.parent.resolve() != corpus.resolve():
            continue
        desc = _parse_skill_description(skill_md)
        if desc:
            skill_name = skill_md.parent.name
            results.append(_SkillDesc(name=skill_name, description=desc))

    return results


def _compute_overlap(
    block: _ReasoningBlock,
    skill: _SkillDesc,
    min_overlap: int = 5,
) -> list[str] | None:
    """Check if a reasoning block's keywords overlap with a skill's description.

    Returns the list of overlapping keywords if overlap >= min_overlap,
    else None.
    """
    block_kws = block.keywords()
    overlap = block_kws & skill.keywords
    if len(overlap) >= min_overlap:
        return sorted(overlap)
    return None


# ── Public API ───────────────────────────────────────────────────────────────

def detect(
    paths: Iterable[str],
    *,
    no_llm: bool = False,
    corpus_dir: str | None = None,
    **_kwargs: Any,
) -> list[dict]:
    """Run inline-reasoning-duplication detection.

    Args:
        paths: SKILL.md paths to audit.
        no_llm: accepted for interface compatibility; ignored (this
            detector is purely deterministic — no LLM needed).
        corpus_dir: directory of sibling skills for cross-skill comparison.
            If None, inferred from the target path's parent directory.

    Returns: findings list per ``references/finding-schema.md``.
        Empty list if SKILL.md <= 200 lines or no overlaps found.
    """
    findings: list[dict] = []
    next_id = 1

    for path in paths:
        p = Path(path)
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        text_lines = text.splitlines()

        # Gate: only trigger for SKILL.md > 200 lines.
        if len(text_lines) <= MIN_SKILL_LINES:
            continue

        # Parse reasoning blocks.
        blocks = _parse_reasoning_blocks(text_lines)
        if not blocks:
            continue

        # Discover sibling skills.
        siblings = _discover_sibling_skills(corpus_dir, path)
        if not siblings:
            continue

        # Check each block against each sibling skill.
        for block in blocks:
            block_text_lower = " ".join(block.lines).lower()

            # Collect all matches for this block, then cap.
            block_matches: list[tuple[list[str], _SkillDesc]] = []

            for skill in siblings:
                # Fix 4: skip if block already references the target skill
                # (delegation already happened).
                skill_slug = skill.name.lower()
                if skill_slug in block_text_lower:
                    continue
                # Also check backtick-quoted references like `skill-name`
                if f"`{skill_slug}`" in block_text_lower:
                    continue

                overlap_kws = _compute_overlap(block, skill)
                if overlap_kws is None:
                    continue
                block_matches.append((overlap_kws, skill))

            # Fix 5: cap findings-per-block at 3 (highest overlap first).
            # If a single block matches >3 skills, it's generic
            # cross-cutting content, not duplicated reasoning.
            block_matches.sort(key=lambda x: len(x[0]), reverse=True)
            for overlap_kws, skill in block_matches[:3]:

                # Build the finding.
                first_line = block.lines[0].strip() if block.lines else ""
                findings.append({
                    "id": f"IRD-{next_id}",
                    "axis": "inline-reasoning-duplication",
                    "severity": "LOW",
                    "confidence": "medium",
                    "title": (
                        f"Inline reasoning overlaps with skill "
                        f"'{skill.name}'"
                    ),
                    "summary": (
                        f"A {block.block_type} reasoning block "
                        f"(~{block.line_count} lines, L{block.start_line}"
                        f"-L{block.end_line}) overlaps with skill "
                        f"'{skill.name}'. Consider delegating via "
                        f"'Invoke Skill {skill.name}' + gate condition."
                    ),
                    "locations": [{
                        "file": str(p),
                        "lines": f"L{block.start_line}-L{block.end_line}",
                    }],
                    "evidence_quote": first_line[:200],
                    "numeric_basis": {
                        "block_lines": block.line_count,
                        "overlap_keywords": overlap_kws,
                    },
                    "suggested_action": (
                        f"Consider delegating to skill '{skill.name}' "
                        f"instead of inlining this reasoning workflow."
                    ),
                    "requires_human": True,
                })
                next_id += 1

    return findings
