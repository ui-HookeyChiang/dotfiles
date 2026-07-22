#!/usr/bin/env python3
"""skill-audit core — detect redundancy + scriptifiable patterns in a SKILL.md.

Pure stdlib. Read-only on the target. Optionally writes a docs-lifecycle spec
to the host repo's proposed/ dir.

LLM dispatch is performed by the main agent per SKILL.md ## LLM advisory step.
This script emits metrics + rule findings (Python deterministic) only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Optional

# yaml_lite lives in advisory/ and was originally lazy-imported only for
# advisory mode. Task 1.A (A1 frontmatter pathology) also needs structured
# YAML parsing in legacy mode (--no-spec / --write-spec), but yaml_lite
# does not support the SKILL.md frontmatter dialect (hyphenated keys,
# `|` literal blocks). We keep the canonical import path here per spec
# R8 Q3 — future detectors can reach it without re-wiring sys.path — and
# fall back to a SKILL-frontmatter-specific parser below for our case.
_advisory_dir = Path(__file__).resolve().parent / "advisory"
if str(_advisory_dir.parent) not in sys.path:
    sys.path.insert(0, str(_advisory_dir.parent))
try:  # pragma: no cover — only fails if advisory/ removed
    from advisory.yaml_lite import parse_yaml as _yaml_lite_parse_yaml  # noqa: F401
except ImportError:
    _yaml_lite_parse_yaml = None  # type: ignore[assignment]


# ---------------------------------------------------------------------------
# Data model

@dataclass
class CodeBlock:
    """A fenced code block in the SKILL.md."""
    lang: str  # "bash", "python", "", etc.
    start_line: int  # 1-indexed, the ``` opener
    end_line: int  # 1-indexed, the ``` closer
    lines: list[str]  # body lines, no fences
    enclosing_header: str = ""  # nearest H2/H3 text above; "" if none
    preceding_prose: str = ""   # concatenated non-blank lines in the paragraph
                                # immediately above the block (≤ 5 lines)
    section_prose: str = ""     # all non-code, non-header prose under the
                                # enclosing H2/H3 (used by Rule C to detect
                                # wrappers documented later in the section)


@dataclass
class Finding:
    """A single audit finding."""
    kind: str  # "R" redundancy / "S" scriptifiable / "I" script-side info / "F" frontmatter (Task 1.A) / "L" broken link (Task 1.B) / "V" unbound var (Detector 6)
    severity: str  # "HIGH" | "MED" | "LOW" | "INFO"
    locations: list[tuple[int, int]]  # list of (start, end) line ranges
    summary: str
    refactor: str
    saved_lines: int

    def label(self, idx: int) -> str:
        return f"{self.kind}{idx} ({self.severity})"


# Threshold at which an advisory metric score projects a passive INFO finding
# into the legacy path (ADR 0005). Distinct from the advisory composite
# THRESHOLD (30): a single metric must score much higher to be notable on its
# own. Only navigability is currently wired in (ADR scope limit).
NAV_PROJECT_THRESHOLD = 85


def project_metric_finding(
    score: float,
    threshold: float,
    kind: str,
    severity: str,
    summary: str,
    refactor: str,
) -> Optional[Finding]:
    """Generic bridge: project an advisory metric score into a legacy Finding.

    Returns a Finding when ``score >= threshold``, else None. The finding has no
    line locations (it is a SKILL.md-level metric, not a span) and no
    saved_lines estimate. Caller picks a passive severity (e.g. INFO) so the
    projection never flips the exit code.
    """
    if score < threshold:
        return None
    return Finding(
        kind=kind,
        severity=severity,
        locations=[],
        summary=summary,
        refactor=refactor,
        saved_lines=0,
    )


# ---------------------------------------------------------------------------
# Parsing

FENCE_RE = re.compile(r"^```(\w*)\s*$")
BASH_CMD_RE = re.compile(
    r"^\s*(?:[A-Z_][A-Z0-9_]*=\S+\s+)*"  # env prefix
    r"(?:bash|sh|python3?|git|gh|cd|ls|cp|mv|rm|mkdir|rmdir|touch|cat|echo|"
    r"printf|grep|rg|sed|awk|find|fdfind|fd|jq|yq|sort|uniq|wc|tail|head|"
    r"cut|tr|tee|export|source|eval|exec|exit|set|trap|test|"
    r"\[\[?|\.|\\\$\(?|\\\$\{?|sudo|make|npm|pip|pytest|node|"
    r"docker|kubectl|helm|terraform|ansible|"
    r"git|gh|gcloud|aws|az)\b"
)
COMMENT_LINE_RE = re.compile(r"^\s*#")
EMPTY_LINE_RE = re.compile(r"^\s*$")
HEADER_RE = re.compile(r"^#{2,3}\s+(.+?)\s*$")
PROSE_WINDOW = 5  # lines

# Context-aware Detector 2 suppression regexes (see spec
# 2026-05-21-skill-audit-detector2-context).
REFERENCE_HEADER_RE = re.compile(
    r"\b(make targets?|commands?|cli\b|reference|cheat ?sheet|"
    r"options?|flags?|examples?|usage|syntax)\b",
    re.IGNORECASE,
)
TEACHING_MARKERS_RE = re.compile(
    r"(teaching form|for illustration|minimal (?:example|form)|"
    r"教學|教学|illustrative|示範|示范|conceptual)",
    re.IGNORECASE,
)
WRAPPER_REF_RE = re.compile(r"`?scripts/[\w.-]+\.(?:sh|py|lua)`?")


def parse_code_blocks(lines: list[str]) -> list[CodeBlock]:
    """Extract all fenced code blocks from a SKILL.md, attaching enclosing
    header and preceding-prose context to each block (used by Detector 2's
    context-aware suppression rules)."""
    # First pass: identify (header, span) regions so we can compute each
    # section's full prose blob for Rule C (wrapper-already-exists, where
    # the wrapper may be documented after the inline teaching block).
    section_prose_by_start: dict[int, str] = {}
    section_header_by_start: dict[int, str] = {}
    section_start = 0
    section_header = ""
    in_code = False
    prose_acc: list[str] = []

    def flush_section(start_idx: int, header: str, prose: list[str]) -> None:
        section_header_by_start[start_idx] = header
        section_prose_by_start[start_idx] = " ".join(prose)

    for idx, line in enumerate(lines):
        if FENCE_RE.match(line):
            in_code = not in_code
            continue
        if in_code:
            continue
        hm = HEADER_RE.match(line)
        if hm:
            flush_section(section_start, section_header, prose_acc)
            section_start = idx
            section_header = hm.group(1)
            prose_acc = []
        elif not EMPTY_LINE_RE.match(line):
            prose_acc.append(line.strip())
    flush_section(section_start, section_header, prose_acc)

    # Build a lookup: for any line index, which section_start is it under.
    section_starts = sorted(section_prose_by_start.keys())

    def section_for(line_idx: int) -> int:
        """Return the section_start key whose region contains line_idx."""
        chosen = 0
        for s in section_starts:
            if s <= line_idx:
                chosen = s
            else:
                break
        return chosen

    # Second pass: extract code blocks, attach context fields.
    blocks: list[CodeBlock] = []
    prose_buffer: list[str] = []  # rolling window of recent non-blank, non-header lines
    i = 0
    while i < len(lines):
        line = lines[i]
        m = FENCE_RE.match(line)
        if m:
            lang = m.group(1) or ""
            start = i + 1  # 1-indexed
            body: list[str] = []
            j = i + 1
            while j < len(lines):
                if FENCE_RE.match(lines[j]):
                    break
                body.append(lines[j])
                j += 1
            end = j + 1  # closing fence, 1-indexed
            if j < len(lines):  # found close
                sec_start = section_for(i)
                blocks.append(CodeBlock(
                    lang=lang,
                    start_line=start,
                    end_line=end,
                    lines=body,
                    enclosing_header=section_header_by_start.get(sec_start, ""),
                    preceding_prose=" ".join(prose_buffer[-PROSE_WINDOW:]),
                    section_prose=section_prose_by_start.get(sec_start, ""),
                ))
                # Reset prose buffer — code blocks break the surrounding
                # paragraph for context purposes.
                prose_buffer = []
                i = j + 1
            else:  # unclosed — bail
                break
            continue

        hm = HEADER_RE.match(line)
        if hm:
            prose_buffer = []
        elif EMPTY_LINE_RE.match(line):
            # Blank line ends the current paragraph; keep the last window for
            # the *next* block but reset accumulation.
            pass
        else:
            prose_buffer.append(line.strip())
        i += 1
    return blocks


# ---------------------------------------------------------------------------
# Detector 1: redundant steps

def normalize_bash_line(line: str) -> str:
    """Normalize a bash line for fuzzy matching: collapse whitespace, strip args."""
    # strip leading $, > prompts
    s = re.sub(r"^\s*[\$>]\s+", "", line)
    # collapse whitespace
    s = re.sub(r"\s+", " ", s).strip()
    return s


def block_signature(block: CodeBlock) -> list[str]:
    """A normalized signature of a code block — used to compare blocks."""
    sig: list[str] = []
    for ln in block.lines:
        if COMMENT_LINE_RE.match(ln) or EMPTY_LINE_RE.match(ln):
            continue
        sig.append(normalize_bash_line(ln))
    return sig


def detect_redundant_blocks(blocks: list[CodeBlock]) -> list[Finding]:
    """Find code blocks with ≥ 3 lines that match across 2+ locations."""
    # Group bash-ish blocks by their signature
    bash_blocks = [b for b in blocks if b.lang in ("bash", "sh", "")]
    by_sig: dict[tuple[str, ...], list[CodeBlock]] = {}
    for b in bash_blocks:
        sig = tuple(block_signature(b))
        if len(sig) < 3:
            continue
        by_sig.setdefault(sig, []).append(b)

    findings: list[Finding] = []
    for sig, instances in by_sig.items():
        if len(instances) < 2:
            continue
        # Severity
        block_lines = len(sig)
        if len(instances) >= 3 or block_lines >= 10:
            severity = "HIGH"
        elif block_lines >= 5:
            severity = "MED"
        else:
            severity = "LOW"
        # First line of signature for the summary
        first_cmd = sig[0][:80] + ("…" if len(sig[0]) > 80 else "")
        locations = [(b.start_line, b.end_line) for b in instances]
        saved = block_lines * (len(instances) - 1)
        findings.append(Finding(
            kind="R",
            severity=severity,
            locations=locations,
            summary=f"Identical bash sequence ({block_lines} cmds) starting with: `{first_cmd}`",
            refactor=f"Extract to `scripts/<verb-name>.sh` with arguments, replace all "
                     f"{len(instances)} call sites with `bash scripts/<verb-name>.sh ...`",
            saved_lines=saved,
        ))
    return findings


def detect_redundant_prose(content: str) -> list[Finding]:
    """Find prose paragraphs (≥ 30 words) that appear in 2+ places."""
    lines = content.splitlines()
    # Build paragraphs from non-fence, non-empty lines
    paragraphs: list[tuple[int, int, str]] = []
    in_fence = False
    para_lines: list[tuple[int, str]] = []  # (line_idx, text)
    for i, ln in enumerate(lines):
        if FENCE_RE.match(ln):
            in_fence = not in_fence
            if para_lines:
                _flush_para(paragraphs, para_lines)
                para_lines = []
            continue
        if in_fence:
            continue
        if EMPTY_LINE_RE.match(ln) or ln.startswith("#"):
            if para_lines:
                _flush_para(paragraphs, para_lines)
                para_lines = []
            continue
        para_lines.append((i, ln))
    if para_lines:
        _flush_para(paragraphs, para_lines)

    # Find duplicate paragraphs (≥ 30 words)
    by_text: dict[str, list[tuple[int, int]]] = {}
    for start, end, text in paragraphs:
        word_count = len(text.split())
        if word_count < 30:
            continue
        # Normalize: collapse whitespace, lowercase
        norm = " ".join(text.lower().split())
        by_text.setdefault(norm, []).append((start + 1, end + 1))  # 1-indexed

    findings: list[Finding] = []
    for norm, locs in by_text.items():
        if len(locs) < 2:
            continue
        word_count = len(norm.split())
        severity = "MED" if word_count >= 60 else "LOW"
        preview = norm[:80] + ("…" if len(norm) > 80 else "")
        findings.append(Finding(
            kind="R",
            severity=severity,
            locations=locs,
            summary=f"Duplicated prose paragraph ({word_count} words): \"{preview}\"",
            refactor="Extract to a single section, reference from both call sites via section anchor",
            saved_lines=word_count // 12 * (len(locs) - 1),  # rough line est
        ))
    return findings


def _flush_para(paragraphs: list[tuple[int, int, str]], buf: list[tuple[int, str]]) -> None:
    if not buf:
        return
    start = buf[0][0]
    end = buf[-1][0]
    text = " ".join(t for _, t in buf)
    paragraphs.append((start, end, text))


# ---------------------------------------------------------------------------
# Detector 2: scriptifiable instructions

# Patterns that indicate a human-judgement interjection (NOT scriptifiable)
JUDGEMENT_HINTS = re.compile(
    r"\b(review|inspect|verify|confirm|decide|if .* then|consider|"
    r"check whether|make sure|carefully|by hand|judgment)\b",
    re.IGNORECASE,
)


def detect_scriptifiable_blocks(blocks: list[CodeBlock]) -> list[Finding]:
    """Code blocks with ≥ 3 chained commands and no judgement interjection."""
    findings: list[Finding] = []
    for b in blocks:
        if b.lang not in ("bash", "sh", ""):
            continue
        # Count real bash commands
        cmds = [ln for ln in b.lines
                if not COMMENT_LINE_RE.match(ln)
                and not EMPTY_LINE_RE.match(ln)
                and BASH_CMD_RE.match(ln)]
        if len(cmds) < 3:
            continue

        # Check for judgement hints in inline comments within the block
        comments = [ln for ln in b.lines if COMMENT_LINE_RE.match(ln)]
        has_judgement = any(JUDGEMENT_HINTS.search(c) for c in comments)
        if has_judgement:
            continue

        # Rule A — reference-header skip: catalog sections like
        # "## Make Targets", "## Commands", "## CLI Reference" document
        # available commands, not executable workflows.
        if REFERENCE_HEADER_RE.search(b.enclosing_header):
            continue

        # Rule B — teaching-marker skip: prose above the block, anywhere in
        # the enclosing H2/H3 section, OR an inline comment inside the block
        # explicitly flags it as illustrative.
        block_comments_text = " ".join(comments)
        if (TEACHING_MARKERS_RE.search(b.preceding_prose)
                or TEACHING_MARKERS_RE.search(b.section_prose)
                or TEACHING_MARKERS_RE.search(block_comments_text)):
            continue

        # Rule C — wrapper-already-exists skip: when the preceding prose or
        # in-block comments mention a sibling `scripts/<x>.sh` wrapper, the
        # inline form is teaching for the wrapper.
        # NOTE: deliberately does NOT consult section_prose. A wrapper mentioned
        # elsewhere in the same H2 section is too weak a signal — many sections
        # legitimately mix wrapper-doc blocks and standalone-workflow blocks
        # (e.g. flow-dev "Pre-merge tasks" section). Use Rule B if the
        # block needs a stronger illustrative signal that can reach further.
        if (WRAPPER_REF_RE.search(b.preceding_prose)
                or WRAPPER_REF_RE.search(block_comments_text)):
            continue

        # Severity
        if len(cmds) >= 8:
            severity = "HIGH"
        elif len(cmds) >= 5:
            severity = "MED"
        else:
            severity = "LOW"

        # Suggest script name from first cmd's verb
        first_word_match = re.match(r"\s*(?:[A-Z_]+=\S+\s+)*(\w+)", cmds[0])
        verb = first_word_match.group(1) if first_word_match else "task"
        script_name = f"{verb}-flow.sh"

        block_lines = b.end_line - b.start_line + 1
        findings.append(Finding(
            kind="S",
            severity=severity,
            locations=[(b.start_line, b.end_line)],
            summary=f"{len(cmds)} chained bash commands with no human-judgement interjection",
            refactor=f"Extract to `scripts/{script_name}` with appropriate arguments, "
                     f"replace block with `bash scripts/{script_name} ...`",
            saved_lines=max(0, block_lines - 1),
        ))
    return findings


# ---------------------------------------------------------------------------
# Frontmatter parsing helpers (Task 1.A — spec 2026-05-29-doc-correctness)

_FRONTMATTER_DELIM = "---"
# Hyphen-allowing key match (yaml_lite forbids hyphens for safety; SKILL.md
# frontmatter uses argument-hint, landing-group, etc.).
_FM_KEY_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*?)\s*$")
# `Skill <name>` reference in body text. The full-word regex; per-line we
# additionally skip lines inside fenced code blocks.
_SKILL_REF_RE = re.compile(r"\bSkill\s+([a-z][a-z0-9_-]*)\b")
# Placeholder allowlist for stale-ref filter (spec L256). These are
# documentation patterns, not real skill references.
_SKILL_REF_PLACEHOLDERS = {"foo", "bar", "baz", "xxx", "yyy", "zzz",
                            "name", "skillname", "skill-name", "your-skill"}
# `<placeholder>` token used as a heuristic for argument-hint drift (Rule 5).
_ANGLE_PLACEHOLDER_RE = re.compile(r"<[A-Za-z][A-Za-z0-9_-]*>")


def _extract_frontmatter_block(content: str) -> tuple[str, int, int]:
    """Return (body_text, start_line_1idx, end_line_1idx) of the frontmatter.

    If the file does not start with `---`, returns ("", 0, 0). end_line is the
    line index of the closing `---` (inclusive). Line numbers are 1-indexed.
    """
    if not content.startswith(_FRONTMATTER_DELIM):
        return "", 0, 0
    lines = content.splitlines()
    if not lines or lines[0].strip() != _FRONTMATTER_DELIM:
        return "", 0, 0
    for i in range(1, len(lines)):
        if lines[i].strip() == _FRONTMATTER_DELIM:
            return "\n".join(lines[1:i]), 1, i + 1  # 1-indexed inclusive
    # unterminated frontmatter
    return "", 0, 0


def _parse_skill_frontmatter(content: str) -> dict:
    """Parse a SKILL.md YAML frontmatter into a flat dict[str, str|None].

    Supports the subset SKILL.md uses in this repo:
      - plain scalars (``key: value``)
      - double/single-quoted strings (``key: "value"``)
      - block literal (``key: |``) — joined with \n preserving the body lines
      - hyphenated keys (``argument-hint:``)

    Out of scope: nested mappings, lists, anchors, folded scalars (``>``),
    quoted multi-line scalars. Anything unrecognized maps to its raw string
    (the detector is defensive — substring/length checks tolerate it).

    Returns ``{}`` if no frontmatter is present or it is unterminated.
    """
    body, _, _ = _extract_frontmatter_block(content)
    if not body:
        return {}
    result: dict = {}
    lines = body.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        m = _FM_KEY_LINE.match(line)
        if not m:
            # Not a key:value line — likely a continuation of a previous value
            # we did not recognize as a literal-block. Skip silently.
            i += 1
            continue
        key, rest = m.group(1), m.group(2)
        if rest == "|" or rest == "|-" or rest == "|+":
            # Literal block: consume indented continuation lines (any indent
            # > 0). Preserve their joined body as the value.
            block: list[str] = []
            i += 1
            while i < len(lines):
                nxt = lines[i]
                if nxt and not nxt[0].isspace() and nxt.strip():
                    break
                # strip the leading common indent (we accept any whitespace
                # indent — SKILL.md frontmatter rarely uses tabs).
                block.append(nxt.lstrip())
                i += 1
            # Trim trailing empty lines
            while block and not block[-1].strip():
                block.pop()
            result[key] = "\n".join(block)
            continue
        # Plain scalar — strip surrounding quotes if symmetrical.
        val = rest
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
            val = val[1:-1]
        result[key] = val
        i += 1
    return result


def _extract_sections(lines: list[str]) -> list[tuple[str, int, int]]:
    """Return [(heading_text, start_line_1idx, end_line_1idx), ...] for each
    H2/H3 section. Line indices are 1-based. The final section's end_line
    is the file's last line."""
    sections: list[tuple[str, int, int]] = []
    in_fence = False
    open_start: int | None = None
    open_heading = ""
    for idx, line in enumerate(lines):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEADER_RE.match(line)
        if m:
            if open_start is not None:
                sections.append((open_heading, open_start, idx))  # idx = 1-based end
            open_start = idx + 1  # 1-based start of new section
            open_heading = m.group(1)
    if open_start is not None:
        sections.append((open_heading, open_start, len(lines)))
    return sections


def _build_parsed_context(
    content: str,
    *,
    lines: list[str] | None = None,
    code_blocks: list[CodeBlock] | None = None,
) -> dict:
    """Build the shared parsed_context dict for Task 1.A+ detectors (spec R9 #1).

    Keys:
      - 'frontmatter': dict from _parse_skill_frontmatter
      - 'lines':       list[str] of SKILL.md raw lines (no trailing newlines)
      - 'sections':    list[(heading, start_1idx, end_1idx)]
      - 'code_blocks': list[CodeBlock]
      - 'frontmatter_range': (start_1idx, end_1idx) for the `---` ... `---` block;
                              (0, 0) if no frontmatter
    """
    if lines is None:
        lines = content.splitlines()
    if code_blocks is None:
        code_blocks = parse_code_blocks(lines)
    _, fm_start, fm_end = _extract_frontmatter_block(content)
    return {
        "frontmatter": _parse_skill_frontmatter(content),
        "lines": lines,
        "sections": _extract_sections(lines),
        "code_blocks": code_blocks,
        "frontmatter_range": (fm_start, fm_end),
    }


# ---------------------------------------------------------------------------
# Detector 4 (Task 1.A): A1 frontmatter pathology

_DESCRIPTION_MAX_CHARS = 1024
_TRIGGER_PHRASES = ("Use when", "Triggers on")
_PLUGIN_ROOT_ENV = "SKILL_AUDIT_PLUGIN_ROOTS"
_DEFAULT_PLUGIN_ROOT = Path("~/.claude/skills").expanduser()


def _get_plugin_skill_oracle() -> set[str]:
    """Return the set of installed-skill dirnames used as a stale-ref oracle.

    Reads ``~/.claude/skills/`` by default. The env var
    ``SKILL_AUDIT_PLUGIN_ROOTS`` overrides with one or more ``:``-separated
    directory paths (mainly for tests — see fixtures/frontmatter/fake_plugin_root/).
    Missing/unreadable directories are silently skipped — stale-ref detection
    is best-effort, never crashes the audit.
    """
    roots_env = os.environ.get(_PLUGIN_ROOT_ENV)
    roots = [Path(p) for p in roots_env.split(":")] if roots_env else [_DEFAULT_PLUGIN_ROOT]
    names: set[str] = set()
    for root in roots:
        try:
            if not root.is_dir():
                continue
            for child in root.iterdir():
                try:
                    # Follow symlinks to dedupe, but track by dirname.
                    if child.is_dir():
                        names.add(child.name)
                except OSError:
                    continue
        except OSError:
            continue
    return names


def _body_lines_excluding_code_fences(
    lines: list[str],
    fm_end: int,
) -> list[tuple[int, str]]:
    """Return [(line_no_1idx, line_text), ...] for body lines outside fences."""
    out: list[tuple[int, str]] = []
    in_fence = False
    for idx, line in enumerate(lines):
        line_no = idx + 1
        if line_no <= fm_end:
            continue
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        out.append((line_no, line))
    return out


def detect_frontmatter_pathology(
    skill_md_path: Path,
    parsed_context: dict,
) -> list[Finding]:
    """A1 detector — 6 frontmatter rules + R9 #3 stale-ref subset.

    Per spec 2026-05-29-doc-correctness Design §Task 1.A.
    """
    fm: dict = parsed_context.get("frontmatter") or {}
    lines: list[str] = parsed_context.get("lines") or []
    fm_start, fm_end = parsed_context.get("frontmatter_range") or (0, 0)
    findings: list[Finding] = []

    # The "anchor" line we point at for frontmatter findings — use the
    # `---` opener if it exists, else line 1 (so locations stay valid).
    fm_anchor: tuple[int, int] = (fm_start or 1, fm_end or 1)

    # Rule 3a: missing description (HIGH) -----------------------------------
    if "description" not in fm:
        findings.append(Finding(
            kind="F", severity="HIGH", locations=[fm_anchor],
            summary="frontmatter missing required key: description",
            refactor="add `description:` to frontmatter — required for skill load and trigger routing",
            saved_lines=0,
        ))
        desc = ""
    else:
        desc = fm.get("description") or ""

    # Rule 3b: missing name (HIGH) ------------------------------------------
    if "name" not in fm:
        findings.append(Finding(
            kind="F", severity="HIGH", locations=[fm_anchor],
            summary="frontmatter missing required key: name",
            refactor="add `name:` to frontmatter matching the parent directory name",
            saved_lines=0,
        ))
        name = ""
    else:
        name = (fm.get("name") or "").strip()

    # Rule 1: description > 1024 chars (HIGH) -------------------------------
    if desc and len(desc) > _DESCRIPTION_MAX_CHARS:
        findings.append(Finding(
            kind="F", severity="HIGH", locations=[fm_anchor],
            summary=(
                f"description exceeds 1024 char limit "
                f"({len(desc)} chars > {_DESCRIPTION_MAX_CHARS})"
            ),
            refactor=(
                "trim description to ≤ 1024 chars or move detail into SKILL.md body. "
                "Plugin loader may truncate / reject overlong descriptions."
            ),
            saved_lines=0,
        ))

    # Rule 2: name != dirname (HIGH) ----------------------------------------
    dirname = Path(skill_md_path).parent.name
    if name and dirname and name != dirname:
        findings.append(Finding(
            kind="F", severity="HIGH", locations=[fm_anchor],
            summary=(
                f"frontmatter name ({name!r}) does not match parent dirname ({dirname!r})"
            ),
            refactor=(
                f"align name with dirname — either rename the directory to "
                f"{name!r} or set name: {dirname}"
            ),
            saved_lines=0,
        ))

    # Rule 4: description without "Use when" / "Triggers on" (MED) ----------
    if desc and not any(phrase in desc for phrase in _TRIGGER_PHRASES):
        findings.append(Finding(
            kind="F", severity="MED", locations=[fm_anchor],
            summary=(
                "description does not contain a trigger phrase "
                "('Use when' or 'Triggers on')"
            ),
            refactor=(
                "add a `Use when ...` or `Triggers on ...` clause so the routing "
                "agent knows when to invoke this skill"
            ),
            saved_lines=0,
        ))

    # Rule 5: argument-hint declared but no `<placeholder>` in body (LOW) ---
    if "argument-hint" in fm:
        # Look for any `<placeholder>` token anywhere in body (including code
        # fences — placeholder examples often live in `bash run.sh <path>`
        # style fenced blocks).
        body_has_placeholder = False
        for idx, line in enumerate(lines):
            if (idx + 1) <= fm_end:
                continue
            if _ANGLE_PLACEHOLDER_RE.search(line):
                body_has_placeholder = True
                break
        if not body_has_placeholder:
            findings.append(Finding(
                kind="F", severity="LOW", locations=[fm_anchor],
                summary=(
                    "frontmatter declares argument-hint but SKILL.md body has no "
                    "`<placeholder>` example"
                ),
                refactor=(
                    "either add a `<placeholder>` example in the body (Usage / CLI "
                    "section) or remove argument-hint if the skill takes no args"
                ),
                saved_lines=0,
            ))

    # Rule 6: landing-group missing (LOW) -----------------------------------
    if "landing-group" not in fm:
        findings.append(Finding(
            kind="F", severity="LOW", locations=[fm_anchor],
            summary="frontmatter missing landing-group key",
            refactor=(
                "add `landing-group:` (e.g. `workflow`, `audit`, `dev`) so the "
                "plugin index can group this skill"
            ),
            saved_lines=0,
        ))

    # Rule 7 (R9 #3 stale-ref): `Skill foo` body refs not in plugin oracle (MED)
    oracle: set[str] = _get_plugin_skill_oracle()
    if oracle:
        for line_no, line in _body_lines_excluding_code_fences(lines, fm_end):
            # Skip lines that are inline-code only? A line with ``Skill nonexistent``
            # backtick-inlined is still a body claim — treat as real reference.
            for m in _SKILL_REF_RE.finditer(line):
                ref = m.group(1).lower()
                if ref in _SKILL_REF_PLACEHOLDERS:
                    continue
                if ref in oracle:
                    continue
                findings.append(Finding(
                    kind="F", severity="MED", locations=[(line_no, line_no)],
                    summary=(
                        f"stale Skill ref: `Skill {m.group(1)}` not found in "
                        f"plugin oracle (~/.claude/skills/)"
                    ),
                    refactor=(
                        f"either install the referenced skill, update the name "
                        f"if renamed, or drop the reference if obsolete"
                    ),
                    saved_lines=0,
                ))

    return findings


# ---------------------------------------------------------------------------
# Detector 8 (Rules 8a-8d): openai.yaml consistency
#
# Each skill should have agents/openai.yaml beside its SKILL.md. This
# detector checks that the yaml file exists and that its policy block stays
# in sync with the frontmatter disable-model-invocation flag.


def _parse_openai_yaml(yaml_path: Path) -> dict:
    """Parse agents/openai.yaml — returns a flat-ish dict.

    Supports the minimal subset used in this repo:
      interface.display_name / interface.short_description
      policy.allow_implicit_invocation
    Returns {} if the file cannot be read or parsed.
    """
    try:
        text = yaml_path.read_text()
    except OSError:
        return {}

    result: dict = {}
    current_section: str = ""
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        # Section header (no leading space): "interface:" or "policy:"
        if line and not line[0].isspace() and line.rstrip().endswith(":"):
            current_section = line.rstrip()[:-1]
            continue
        # Key: value under section
        m = re.match(r"^\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$", line)
        if m and current_section:
            key = f"{current_section}.{m.group(1)}"
            val = m.group(2)
            # Strip surrounding quotes if symmetrical
            if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
                val = val[1:-1]
            result[key] = val
    return result


def detect_openai_yaml_consistency(
    skill_dir: Path,
    parsed_context: dict,
) -> list[Finding]:
    """Rules 8a-8d — openai.yaml existence and policy consistency.

    8a HIGH: SKILL.md exists but agents/openai.yaml missing
    8b HIGH: frontmatter has disable-model-invocation: true but yaml lacks
             policy.allow_implicit_invocation: false
    8c HIGH: yaml has policy.allow_implicit_invocation: false but frontmatter
             lacks disable-model-invocation: true
    8d LOW:  yaml exists but display_name or short_description empty/missing
    """
    fm: dict = parsed_context.get("frontmatter") or {}
    fm_start, fm_end = parsed_context.get("frontmatter_range") or (0, 0)
    fm_anchor: tuple[int, int] = (fm_start or 1, fm_end or 1)

    findings: list[Finding] = []

    yaml_path = skill_dir / "agents" / "openai.yaml"

    # Rule 8a: yaml missing
    if not yaml_path.is_file():
        findings.append(Finding(
            kind="F", severity="HIGH", locations=[fm_anchor],
            summary="Rule 8a: agents/openai.yaml missing",
            refactor=(
                "create agents/openai.yaml with interface.display_name and "
                "interface.short_description populated from frontmatter"
            ),
            saved_lines=0,
        ))
        return findings  # remaining rules all require the file to exist

    yaml_data = _parse_openai_yaml(yaml_path)

    # Rule 8b: frontmatter disables invocation but yaml does not
    fm_disabled = (fm.get("disable-model-invocation") or "").strip().lower() == "true"
    yaml_no_implicit = (
        yaml_data.get("policy.allow_implicit_invocation", "").strip().lower() == "false"
    )

    if fm_disabled and not yaml_no_implicit:
        findings.append(Finding(
            kind="F", severity="HIGH", locations=[fm_anchor],
            summary=(
                "Rule 8b: frontmatter has disable-model-invocation: true but "
                "agents/openai.yaml lacks policy.allow_implicit_invocation: false"
            ),
            refactor=(
                "add a policy block to agents/openai.yaml:\n"
                "  policy:\n"
                "    allow_implicit_invocation: false"
            ),
            saved_lines=0,
        ))

    # Rule 8c: yaml disables invocation but frontmatter does not
    if yaml_no_implicit and not fm_disabled:
        findings.append(Finding(
            kind="F", severity="HIGH", locations=[fm_anchor],
            summary=(
                "Rule 8c: agents/openai.yaml has policy.allow_implicit_invocation: false "
                "but frontmatter lacks disable-model-invocation: true"
            ),
            refactor=(
                "add `disable-model-invocation: true` to SKILL.md frontmatter "
                "to match the openai.yaml policy block"
            ),
            saved_lines=0,
        ))

    # Rule 8d: yaml exists but display_name or short_description is empty/missing
    display_name = yaml_data.get("interface.display_name", "").strip()
    short_description = yaml_data.get("interface.short_description", "").strip()
    if not display_name or not short_description:
        findings.append(Finding(
            kind="F", severity="LOW", locations=[(1, 1)],
            summary=(
                "Rule 8d: agents/openai.yaml missing or empty "
                + ("display_name" if not display_name else "short_description")
            ),
            refactor=(
                "populate interface.display_name and interface.short_description "
                "in agents/openai.yaml (max ~80 chars each)"
            ),
            saved_lines=0,
        ))

    return findings


# ---------------------------------------------------------------------------
# Detector 5 (Task 1.B): A2 broken links
#
# Per spec 2026-05-29-doc-correctness Design §Task 1.B. Picks up 4 reference
# types (references/<file>, scripts/<file>, relative-path markdown link,
# internal #anchor) and resolves against the FS + slugified-heading set.
# Severity routed by enclosing H2 section. Includes Levenshtein typo hint for
# anchors via difflib. Includes context-aware FP filter (2026-05-30 dogfood:
# 7 candidates / 6 FPs without filter -> target <= 15% with filter).

from difflib import get_close_matches

# --- Reference extractors --------------------------------------------------
_REF_REFERENCES_RE = re.compile(r"references/[A-Za-z0-9._/-]+\.(?:md|json|yaml|yml|txt)")
_REF_SCRIPTS_RE = re.compile(r"scripts/[A-Za-z0-9._/-]+\.(?:sh|py|js|mjs)")
_MD_LINK_RE = re.compile(r'\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
_ANCHOR_LINK_RE = re.compile(r"\]\(#([a-z0-9][a-z0-9-]*)\)")

# --- Context-aware FP filter regexes --------------------------------------
_INLINE_CODE_HINT_RE = re.compile(
    r"(?:\bexample\b|\be\.g\.|\bproposed\b|\bextract to\b|範例|示例|示範)",
    re.IGNORECASE,
)
_FUTURE_TENSE_RE = re.compile(
    r"(?:\bwill\b|\bextract to\b|\bfuture\b|\bplanned\b|\bonce we\b|\bto clean this up\b|未來|將會|計畫)",
    re.IGNORECASE,
)
_ABS_PATH_RE = re.compile(r"/(?:home|usr|opt|var|tmp|root|etc)/[A-Za-z0-9._/-]+")
_OTHER_SKILL_PREFIX_RE = re.compile(
    r"\b(?:skill-[a-z][a-z0-9-]+|[a-z][a-z0-9-]+-skill|prose-[a-z][a-z0-9-]+|darwin|stack-dev|skill-creator|skill-writer)\b",
    re.IGNORECASE,
)


def _slugify_heading(heading: str) -> str:
    """GitHub-style slugify (lowercase, drop punctuation, hyphenate whitespace).

    Examples:
      ``## Phase 2: Detect`` -> ``phase-2-detect``
      ``### Why this design?`` -> ``why-this-design``
    Per spec L304-316.
    """
    s = heading.lower().lstrip("#").strip()
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"[^a-z0-9-]", "", s)
    return s


def _section_for_line(sections: list[tuple[str, int, int]], line_no: int) -> str:
    """Return the H2/H3 heading text whose range contains line_no, else ""."""
    for heading, start, end in sections:
        if start <= line_no <= end:
            return heading
    return ""


def _section_severity(heading: str) -> str:
    """Path-type severity by section context (spec L325-328)."""
    h = heading.lower()
    if any(kw in h for kw in ("when to use", "cli usage", "workflow")):
        return "HIGH"
    if any(kw in h for kw in ("references", "see also")):
        return "MED"
    if any(kw in h for kw in ("why this design", "background", "rationale", "history", "notes")):
        return "LOW"
    return "MED"


def _anchor_severity(heading: str, is_typo_hint: bool) -> str:
    """Anchor severity (spec L330-333)."""
    if is_typo_hint:
        return "LOW"
    h = heading.lower()
    if any(kw in h for kw in ("when to use", "workflow")):
        return "HIGH"
    return "MED"


def _is_inside_inline_code(line: str, ref: str) -> bool:
    """Check whether ref occurs inside backtick-bounded inline code on this line."""
    idx = line.find(ref)
    if idx < 0:
        return False
    pre = line[:idx]
    post = line[idx + len(ref):]
    # An inline code span has an opening backtick before with matching close after.
    # Count unescaped backticks in pre. Odd -> inside code.
    pre_ticks = pre.count("`")
    post_ticks = post.count("`")
    return (pre_ticks % 2 == 1) and (post_ticks >= 1)


def _ref_suppressed_by_context(
    ref: str,
    line_no: int,
    lines: list[str],
    sections: list[tuple[str, int, int]],
    skill_dir: Path | None = None,
) -> tuple[bool, str]:
    """Apply context-aware FP filters. Return (suppress, reason).

    Rule A: ref in backtick inline code AND same-line has example/e.g./Proposed/extract to/範例.
    Rule B: future-tense keyword (will / extract to / 未來) within +/-5 lines.
    Rule C1 (path prefix): same line has `<other-skill>/<ref>` substring. If the
            resolved cross-skill path EXISTS in repo, the ref points at a real file
            elsewhere -> suppress (true cross-skill ref). If the cross-skill path
            does NOT exist either, the ref is genuinely broken even with prefix
            -> do NOT suppress (preserve TP signal).
    Rule C2 (name only): same +/-5 line window contains an other-skill name
            mention without an embedded full path. Per spec L295 ('明確 skill name 前綴')
            suppress unconditionally — author is talking about another skill, not
            claiming a local file at <skill_dir>/<ref>.
    Rule D: same +/-5 line window contains absolute /home/... path -> suppress.
    """
    line = lines[line_no - 1] if 0 < line_no <= len(lines) else ""

    # Rule A: inline-code + same-line keyword
    if _is_inside_inline_code(line, ref) and _INLINE_CODE_HINT_RE.search(line):
        return True, "inline-code example/proposed phrasing"

    # Rule B: future-tense within +/-5 lines
    lo = max(1, line_no - 5)
    hi = min(len(lines), line_no + 5)
    window = "\n".join(lines[lo - 1:hi])
    if _FUTURE_TENSE_RE.search(window):
        return True, "future-tense within +/-5 lines"

    # Rule C1: explicit cross-skill path prefix on same line.
    # Path-prefix form: `skill-foo/<ref>` appears literally in line.
    # Suppress only when the resolved cross-skill path exists; if absent, the
    # author wrote a broken ref WITH explicit prefix and the finding stands.
    path_prefixed = False
    if skill_dir is not None:
        for m in _OTHER_SKILL_PREFIX_RE.finditer(line):
            prefix = m.group(0)
            candidate = f"{prefix}/{ref}"
            if candidate in line:
                path_prefixed = True
                repo_root = skill_dir.parent
                resolved_cross = (repo_root / candidate).resolve()
                if resolved_cross.exists():
                    return True, f"cross-skill ref resolves at {resolved_cross}"

    # Rule C2: name-only prefix (no full path attached).
    # The window has an other-skill name mention but no `<skill>/<ref>` substring
    # locally. Author is discussing another skill -> suppress per spec L295.
    if not path_prefixed and _OTHER_SKILL_PREFIX_RE.search(window):
        return True, "other-skill name prefix present in same paragraph"

    # Rule D: same window contains absolute path
    if _ABS_PATH_RE.search(window):
        return True, "absolute path present in same paragraph"

    return False, ""


def _body_lines_excluding_fences_full(
    lines: list[str],
    fm_end: int,
) -> list[tuple[int, str]]:
    """Body lines outside frontmatter and fenced code blocks."""
    out: list[tuple[int, str]] = []
    in_fence = False
    for idx, line in enumerate(lines):
        line_no = idx + 1
        if line_no <= fm_end:
            continue
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        out.append((line_no, line))
    return out


def detect_broken_links(
    skill_md_path: Path,
    parsed_context: dict,
    skill_root: Path | None = None,
) -> list[Finding]:
    """A2 detector — 4 reference types resolved against FS + heading slug set.

    Per spec 2026-05-29-doc-correctness Design §Task 1.B.

    skill_root: when provided, path-link resolution uses this directory instead
    of the target file's parent. Enables correct auditing of reference files
    (references/*.md) whose path-links resolve against the TRUE skill root, not
    against the references/ subdirectory. Default (None) uses target parent —
    byte-identical behaviour when skill_root == target parent (i.e. SKILL.md).
    """
    lines: list[str] = parsed_context.get("lines") or []
    sections: list[tuple[str, int, int]] = parsed_context.get("sections") or []
    fm_start, fm_end = parsed_context.get("frontmatter_range") or (0, 0)
    # Two resolution bases: a path-link is OK if it resolves under EITHER.
    #  root_base — the TRUE skill root (skill_root when passed; else the target's
    #    own parent). Resolves `scripts/x.sh` / `references/x.md` style refs that
    #    address the skill root from inside a references/*.md file.
    #  file_base — the citing file's own directory. Resolves a bare SIBLING ref
    #    (e.g. `equivalence-criteria.md` linked from another references/*.md),
    #    which is a relative link against the citing file, not the skill root.
    # When skill_root is None (auditing SKILL.md) both bases are the same parent,
    # so behaviour is byte-identical to before.
    root_base = skill_root if skill_root is not None else Path(skill_md_path).parent
    file_base = Path(skill_md_path).parent
    skill_dir = root_base  # Rule-C cross-skill resolution keys off the skill root

    # Build slugified heading set for anchor checks.
    heading_slugs = {_slugify_heading(h) for h, _, _ in sections}

    findings: list[Finding] = []
    seen: set[tuple[str, int]] = set()  # (ref, line_no) dedupe within one file

    body = _body_lines_excluding_fences_full(lines, fm_end)

    # --- Path-type references (references/, scripts/, relative md links) ---
    for line_no, line in body:
        # Skip URL-like content fast (http://, https://) to avoid matching
        # `references/` substrings inside URLs.
        # We still scan for the regexes but drop matches whose surrounding
        # context looks URL-shaped.
        candidates: list[tuple[str, str]] = []  # (ref, kind_label)
        for m in _REF_REFERENCES_RE.finditer(line):
            candidates.append((m.group(0), "references"))
        for m in _REF_SCRIPTS_RE.finditer(line):
            candidates.append((m.group(0), "scripts"))
        # Markdown relative-path links: ](path). Skip http(s), absolute, anchor-only.
        for m in _MD_LINK_RE.finditer(line):
            target = m.group(1).strip()
            if not target:
                continue
            if target.startswith(("http://", "https://", "mailto:", "ftp://", "#")):
                continue
            if target.startswith("/"):
                # absolute on host FS — out of scope (treat as external)
                continue
            # If it matches references/ or scripts/ we already counted it.
            if _REF_REFERENCES_RE.search(target) or _REF_SCRIPTS_RE.search(target):
                continue
            candidates.append((target, "relative"))

        for ref, kind_label in candidates:
            key = (ref, line_no)
            if key in seen:
                continue
            seen.add(key)
            # URL contamination guard: e.g. `https://github.com/foo/references/bar.md`
            # would have matched but the http(s) prefix on the same line means
            # the regex picked up a substring of a URL. We require that the
            # match position not be preceded by "://" on the same line within 80
            # chars.
            ref_idx = line.find(ref)
            preceding = line[max(0, ref_idx - 80):ref_idx]
            if "://" in preceding and "(" not in preceding[preceding.find("://"):]:
                continue
            # Strip a trailing "?" / ")" if regex picked it up incidentally
            ref_clean = ref.rstrip(").,;:")
            # Resolve against skill_dir; reject absolute paths (host-FS scope)
            ref_path = Path(ref_clean)
            if ref_path.is_absolute():
                continue
            resolved = (root_base / ref_clean).resolve()
            resolved_file_base = (file_base / ref_clean).resolve()
            # OK if the ref resolves under EITHER base. Out-of-skill traversal
            # (../../foo) is still broken iff absent under both.
            if resolved.exists() or resolved_file_base.exists():
                continue
            # Apply FP filter (Rule C needs skill_dir for cross-skill resolution)
            suppress, reason = _ref_suppressed_by_context(
                ref, line_no, lines, sections, skill_dir=skill_dir,
            )
            if suppress:
                continue
            heading = _section_for_line(sections, line_no)
            sev = _section_severity(heading)
            findings.append(Finding(
                kind="L", severity=sev, locations=[(line_no, line_no)],
                summary=(
                    f"{ref_clean} not found "
                    f"(referenced at line {line_no}"
                    f"{', section ' + heading if heading else ''})"
                ),
                refactor=(
                    f"create file at `{ref_clean}` (resolved: {resolved}) "
                    f"or update reference to a valid path"
                ),
                saved_lines=0,
            ))

    # --- Anchor references (#slug) ---
    for line_no, line in body:
        for m in _ANCHOR_LINK_RE.finditer(line):
            slug = m.group(1)
            if slug in heading_slugs:
                continue
            heading = _section_for_line(sections, line_no)
            # Levenshtein-ish hint via difflib.get_close_matches
            close = get_close_matches(slug, list(heading_slugs), n=1, cutoff=0.7)
            if close:
                sev = _anchor_severity(heading, is_typo_hint=True)
                hint = f" Did you mean `#{close[0]}`?"
            else:
                sev = _anchor_severity(heading, is_typo_hint=False)
                hint = ""
            findings.append(Finding(
                kind="L", severity=sev, locations=[(line_no, line_no)],
                summary=(
                    f"anchor `#{slug}` not found among H2/H3 slugs "
                    f"(referenced at line {line_no})"
                ),
                refactor=(
                    f"fix anchor target or rename heading to match slug `{slug}`."
                    + hint
                ),
                saved_lines=0,
            ))

    return findings


# ---------------------------------------------------------------------------
# Detector 3 (passive): script-side redundancy

def detect_script_side_redundancy(scripts_dir: Path) -> list[Finding]:
    """Walk scripts/ and find identical multi-line setup blocks across scripts."""
    if not scripts_dir.is_dir():
        return []

    scripts: list[tuple[Path, list[str]]] = []
    for f in scripts_dir.rglob("*"):
        if f.is_file() and f.suffix in (".sh", ".bash", ".py"):
            try:
                scripts.append((f, f.read_text().splitlines()))
            except (OSError, UnicodeDecodeError):
                continue

    # Compare first 30 non-empty non-comment lines of each script
    findings: list[Finding] = []
    sigs: dict[tuple[str, ...], list[Path]] = {}
    for path, lines in scripts:
        head = [ln.strip() for ln in lines
                if ln.strip() and not ln.strip().startswith("#")][:20]
        if len(head) < 5:
            continue
        sigs.setdefault(tuple(head), []).append(path)

    for sig, paths in sigs.items():
        if len(paths) < 2:
            continue
        findings.append(Finding(
            kind="I",
            severity="INFO",
            locations=[(0, 0)],
            summary=f"Scripts share identical {len(sig)}-line head: " + ", ".join(p.name for p in paths),
            refactor="Consider extracting common setup to a sourced helper script",
            saved_lines=len(sig) * (len(paths) - 1),
        ))
    return findings


# ---------------------------------------------------------------------------
# Detector 6 (kind="V"): unbound bash variables
#
# Scans bash fences in the TARGET SKILL.md for $VAR / ${VAR} references that
# are never bound anywhere in the file (in-file assignment, loop var, export,
# capture, or via a sourced script). Passive / INFO — never flips exit code.

# Regex to find bash fences with their line offsets later.
# (We iterate CodeBlock objects from parse_code_blocks, so no extra parse needed.)

# VAR reference patterns — match $VARNAME and ${VARNAME} (bare name only, no operators).
# Must NOT match: positional $1-$9, $0, $@, $*, $#, $?, $$, $!, $-,
#                 operator expansions ${VAR:-x} ${VAR:=x} ${VAR:?x} ${VAR:+x},
#                 array refs ${arr[i]}.
_UNBOUND_REF_RE = re.compile(
    r"""
    \$\{                              # ${...
        ([A-Za-z_][A-Za-z0-9_]*)     # capture: bare name (no operator, no index)
        (?![:[{*@!])                  # not followed by : [ { * @ ! (operators / array)
    \}
    |
    \$([A-Za-z_][A-Za-z0-9_]*)       # $NAME (bare, no braces)
    """,
    re.VERBOSE,
)

# Operator-expansion: ${VAR:-x} ${VAR:=x} ${VAR:?x} ${VAR:+x} — exclude these entirely.
# Also ${VAR} alone is fine (covered above). The colon-operator form catches all four.
_OPERATOR_EXPANSION_RE = re.compile(
    r"\$\{[A-Za-z_][A-Za-z0-9_]*:[=?:+-]"  # ${VAR:op where op ∈ - = ? +
)

# Positional / special shell params — always skip.
_SPECIAL_PARAMS = frozenset(
    ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
     "@", "*", "#", "?", "$", "!", "-"]
)

# Binding patterns in bash lines (in-file or in sourced script):
#   VAR=...     VAR=$(...) capture     export VAR[= ...]
#   for VAR in / read VAR / while read VAR
_ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
_EXPORT_RE = re.compile(r"\bexport\s+([A-Za-z_][A-Za-z0-9_]*)")
_FOR_RE = re.compile(r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b")
_READ_RE = re.compile(r"\bread(?:\s+-[a-zA-Z]+)*\s+([A-Za-z_][A-Za-z0-9_]*)")

# Source directives in a bash fence line: `source X` or `. X`
_SOURCE_RE = re.compile(r"^\s*(?:source|\.)\s+(\S+)")


def _load_known_env(scripts_dir: Path) -> set[str]:
    """Load known-env.txt; return (exact_names, prefix_globs) as a single callable-like set.

    Implements a small set subclass to handle prefix globs (trailing *).
    If the file is missing, return the POSIX minimum only.
    """
    txt_path = scripts_dir / "known-env.txt"
    exact: set[str] = set()
    prefixes: list[str] = []  # prefix strings (without the trailing *)

    if txt_path.is_file():
        for raw_line in txt_path.read_text().splitlines():
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            if line.endswith("*"):
                prefixes.append(line[:-1])
            else:
                exact.add(line)

    class _KnownEnv:
        """Behaves like a set but also matches prefix globs."""

        def __contains__(self, name: object) -> bool:
            if not isinstance(name, str):
                return False
            if name in exact:
                return True
            return any(name.startswith(p) for p in prefixes)

    return _KnownEnv()  # type: ignore[return-value]


def _collect_bindings_from_lines(text_lines: list[str]) -> set[str]:
    """Return the set of variable names bound in a list of bash lines."""
    bound: set[str] = set()
    for line in text_lines:
        # strip leading whitespace for pattern matching
        stripped = line.lstrip()
        # VAR= assignment (also covers VAR=$(...) capture)
        m = _ASSIGN_RE.match(stripped)
        if m:
            bound.add(m.group(1))
        # export VAR
        for m in _EXPORT_RE.finditer(line):
            bound.add(m.group(1))
        # for VAR in ...
        for m in _FOR_RE.finditer(line):
            bound.add(m.group(1))
        # read VAR / while read VAR
        for m in _READ_RE.finditer(line):
            bound.add(m.group(1))
    return bound


def _strip_single_quotes(s: str) -> str:
    """Replace single-quoted spans '...' with spaces (same length), preserving
    indexing for the caller."""
    result = list(s)
    i = 0
    while i < len(s):
        if s[i] == "'":
            j = s.find("'", i + 1)
            if j == -1:
                break  # unclosed quote — leave rest as-is
            for k in range(i, j + 1):
                result[k] = " "
            i = j + 1
        else:
            i += 1
    return "".join(result)


def _strip_comment(s: str) -> str:
    """Strip a trailing bash comment (#), but NOT inside a quoted string or $-expansion.

    Very conservative: just find the first unquoted, unescaped #.
    Single-quoted spans are stripped first via _strip_single_quotes.
    Double-quote nesting is not fully parsed; this is a best-effort guard.
    """
    # Remove single-quoted spans first (literal, no expansion).
    no_sq = _strip_single_quotes(s)
    # Now scan for # not inside ${...} and not preceded by \.
    # We track brace depth for ${} to skip # inside param expansions.
    in_dq = False
    brace_depth = 0
    i = 0
    while i < len(no_sq):
        c = no_sq[i]
        if c == "\\" and not in_dq:
            i += 2
            continue
        if c == '"':
            in_dq = not in_dq
        elif c == "$" and i + 1 < len(no_sq) and no_sq[i + 1] == "{":
            brace_depth += 1
            i += 2
            continue
        elif c == "}" and brace_depth > 0:
            brace_depth -= 1
        elif c == "#" and not in_dq and brace_depth == 0:
            return s[:i]  # return original (not no_sq) up to this position
        i += 1
    return s


def _extract_refs_from_line(
    line: str,
    base_line_no: int,
) -> list[tuple[str, int]]:
    """Return list of (var_name, line_no) for non-excluded $VAR / ${VAR} refs.

    Applies guards:
      1. Strip # comments.
      2. Skip single-quoted '...' spans.
      3. Operator expansions ${VAR:op} are skipped entirely.
      4. Positional / special params ($1 $@ etc.) are skipped.
    """
    # Guard 1: strip comment
    line = _strip_comment(line)
    # Guard 2: replace single-quoted spans with spaces
    line = _strip_single_quotes(line)
    # Guard 3: blank out operator expansions so the main RE doesn't match inside them
    line = _OPERATOR_EXPANSION_RE.sub(lambda m: " " * len(m.group()), line)

    refs: list[tuple[str, int]] = []
    for m in _UNBOUND_REF_RE.finditer(line):
        name = m.group(1) or m.group(2)
        # Guard 4: skip positional / special
        if name in _SPECIAL_PARAMS:
            continue
        refs.append((name, base_line_no))
    return refs


def _process_fence_for_refs(
    block: CodeBlock,
) -> tuple[list[tuple[str, int]], list[str]]:
    """Return (refs, source_paths) for a bash fence.

    refs = [(var_name, 1-indexed-line-no), ...]
    source_paths = relative paths that the fence `source`s or `.`-includes.
    Heredoc bodies: <<'QUOTED' (literal) are blanked out; unquoted <<EOF bodies are scanned.
    """
    refs: list[tuple[str, int]] = []
    source_paths: list[str] = []

    # Track heredoc state.
    in_heredoc_literal = False   # inside <<'QUOTED' or <<"QUOTED" — skip
    in_heredoc_unquoted = False  # inside <<EOF — scan
    heredoc_delim: str = ""

    for offset, raw_line in enumerate(block.lines):
        line_no = block.start_line + offset  # 1-indexed

        # Heredoc end detection
        if in_heredoc_literal or in_heredoc_unquoted:
            stripped = raw_line.rstrip()
            if stripped == heredoc_delim:
                in_heredoc_literal = False
                in_heredoc_unquoted = False
                heredoc_delim = ""
            elif in_heredoc_unquoted:
                refs.extend(_extract_refs_from_line(raw_line, line_no))
            # literal heredoc body — skip
            continue

        # Heredoc start detection: <<'DELIM' <<"DELIM" or <<DELIM
        hd_m = re.search(r"<<(['\"])([A-Za-z_][A-Za-z0-9_]*)(\1)", raw_line)
        if hd_m:
            in_heredoc_literal = True
            heredoc_delim = hd_m.group(2)
            # still scan the line the <<DELIM appears on (not the body yet)
            refs.extend(_extract_refs_from_line(raw_line, line_no))
            continue

        hd_uq = re.search(r"<<([A-Za-z_][A-Za-z0-9_]*)", raw_line)
        if hd_uq:
            in_heredoc_unquoted = True
            heredoc_delim = hd_uq.group(1)
            # scan trigger line, then body
            refs.extend(_extract_refs_from_line(raw_line, line_no))
            continue

        # Source directive detection (before extracting refs from this line)
        src_m = _SOURCE_RE.match(raw_line)
        if src_m:
            source_paths.append(src_m.group(1))

        refs.extend(_extract_refs_from_line(raw_line, line_no))

    return refs, source_paths


def _resolve_sourced_bindings(source_paths: list[str], skill_dir: Path) -> set[str]:
    """Return var names bound in scripts sourced by the fence.

    Only `source X` / `. X` count — `bash X.sh` subprocesses do NOT.
    Resolves X relative to skill_dir.
    """
    bound: set[str] = set()
    for rel in source_paths:
        # Clean up path: strip quotes, shell variable expansions, etc.
        # If the path contains a $-expansion, we can't resolve it statically.
        if "$" in rel or "`" in rel:
            continue
        # Strip surrounding quotes
        if len(rel) >= 2 and rel[0] in ('"', "'") and rel[-1] == rel[0]:
            rel = rel[1:-1]
        # Resolve relative to skill_dir
        candidate = (skill_dir / rel).resolve()
        if candidate.is_file():
            try:
                lines = candidate.read_text().splitlines()
                bound.update(_collect_bindings_from_lines(lines))
            except OSError:
                pass
    return bound


def detect_unbound_vars(
    blocks: list[CodeBlock],
    skill_dir: Path,
    scripts_dir: Path,
) -> list[Finding]:
    """Detector 6 — find $VAR / ${VAR} in bash fences with no in-file binding.

    Passive (INFO severity). Never flips the exit code.
    One finding per distinct unbound var name, listing all line numbers.

    known-env.txt is always loaded from audit.py's own scripts/ dir (the
    auditor's data file), not from the target skill's scripts/ dir.
    scripts_dir is used only for resolving sourced scripts.
    """
    # Load known-env.txt from audit.py's own directory (always skill-audit/scripts/).
    _auditor_scripts = Path(__file__).resolve().parent
    known_env = _load_known_env(_auditor_scripts)

    # Collect in-file bindings from ALL bash fences (the whole SKILL.md).
    bash_blocks = [b for b in blocks if b.lang in ("bash", "sh")]
    all_lines: list[str] = []
    for b in bash_blocks:
        all_lines.extend(b.lines)
    infile_bound = _collect_bindings_from_lines(all_lines)

    # Per-fence: collect refs + source-resolved bindings.
    # unbound_map: var_name -> list of line numbers where it appears unbound.
    unbound_map: dict[str, list[int]] = {}

    for block in bash_blocks:
        refs, source_paths = _process_fence_for_refs(block)
        sourced_bound = _resolve_sourced_bindings(source_paths, skill_dir)
        all_bound = infile_bound | sourced_bound

        for name, line_no in refs:
            if name in all_bound:
                continue
            if name in known_env:
                continue
            unbound_map.setdefault(name, []).append(line_no)

    if not unbound_map:
        return []

    findings: list[Finding] = []
    for var_name in sorted(unbound_map):
        line_nos = sorted(set(unbound_map[var_name]))
        locations = [(ln, ln) for ln in line_nos]
        findings.append(Finding(
            kind="V",
            severity="INFO",
            locations=locations,
            summary=f"unbound variable: ${var_name} (referenced but never bound in-file)",
            refactor=(
                f"add a guard `: \"${{{var_name}:?set by <X>}}\"` near the fence, "
                f"or document who binds `{var_name}` in a contract line above the block"
            ),
            saved_lines=0,
        ))
    return findings


# ---------------------------------------------------------------------------
# Host repo / docs-lifecycle resolution

def find_docs_lifecycle_root(start: Path) -> Optional[Path]:
    """Walk up from `start` to find `.docs-lifecycle.json`. Return repo root or None."""
    p = start.resolve()
    while p != p.parent:
        if (p / ".docs-lifecycle.json").exists():
            return p
        p = p.parent
    return None


def load_lifecycle_config(root: Path) -> dict:
    return json.loads((root / ".docs-lifecycle.json").read_text())


# ---------------------------------------------------------------------------
# Report + spec generation

def render_report(
    target: Path,
    skill_name: str,
    total_lines: int,
    scripts_dir: Optional[Path],
    findings: list[Finding],
    spec_path: Optional[Path],
    spec_inline: Optional[str] = None,
    host_root: Optional[Path] = None,
) -> str:
    """Render the diagnostic report as Markdown."""
    # Group findings
    redundancy = [f for f in findings if f.kind == "R"]
    scriptifiable = [f for f in findings if f.kind == "S"]
    info = [f for f in findings if f.kind == "I"]
    frontmatter = [f for f in findings if f.kind == "F"]  # Task 1.A
    links = [f for f in findings if f.kind == "L"]  # Task 1.B
    unbound = [f for f in findings if f.kind == "V"]  # Detector 6

    def count_by_sev(group: list[Finding], sev: str) -> int:
        return sum(1 for f in group if f.severity == sev)

    total_saved = sum(f.saved_lines for f in findings if f.severity in ("HIGH", "MED"))

    # Honest spec status line: distinguish written / preview-mode / no-host /
    # explicitly suppressed / no-findings. `spec_inline` carries the preview
    # text; absence means --no-spec or no findings. `host_root` is None only
    # when no findings (we don't bother resolving the host then) or when the
    # walk-up failed (no .docs-lifecycle.json found).
    if spec_path:
        spec_status = f"written to {spec_path}"
    elif spec_inline and host_root:
        spec_status = f"preview only (host `.docs-lifecycle.json` config at {host_root} — re-run with --write-spec to commit)"
    elif spec_inline:
        spec_status = "preview only (no host `.docs-lifecycle.json` config found — copy preview body manually)"
    elif not findings:
        spec_status = "n/a (no findings)"
    else:
        # findings exist but --no-spec was passed
        spec_status = "suppressed by --no-spec"

    out = [
        f"# skill-audit report: {skill_name}",
        "",
        f"**Target**: `{target}`",
        f"**Total lines**: {total_lines}",
        f"**Scripts dir**: {scripts_dir if scripts_dir else '(none)'}",
        f"**Spec**: {spec_status}",
        "",
        "## Bloat metrics",
        "",
        "| Severity | Redundancy | Scriptifiable | Script-side info | Frontmatter | Links | Unbound vars |",
        "|---|---|---|---|---|---|---|",
    ]
    for sev in ("HIGH", "MED", "LOW"):
        r = count_by_sev(redundancy, sev)
        s = count_by_sev(scriptifiable, sev)
        i = count_by_sev(info, sev) if sev == "LOW" else ""
        fm_count = count_by_sev(frontmatter, sev)
        l_count = count_by_sev(links, sev)
        out.append(f"| {sev} | {r} | {s} | {i} | {fm_count} | {l_count} | — |")
    out.append(f"| INFO | — | — | {count_by_sev(info, 'INFO')} | — | — | {len(unbound)} |")
    out.append(
        f"| **Total findings** | **{len(redundancy)}** | **{len(scriptifiable)}** "
        f"| **{len(info)}** | **{len(frontmatter)}** | **{len(links)}** | **{len(unbound)}** |"
    )
    out.append("")
    out.append(f"**Estimated lines saved if all HIGH+MED applied: {total_saved}**")
    out.append("")

    if not findings:
        out.append("## Findings")
        out.append("")
        out.append("> No findings detected.")
        out.append(">")
        out.append("> This skill passed both detectors. No redundancy ≥ 3 lines × 2 "
                   "locations, no scriptifiable blocks ≥ 3 chained commands without "
                   "judgement interjection.")
        return "\n".join(out)

    out.append("## Findings")
    out.append("")

    counter = {"R": 0, "S": 0, "I": 0, "F": 0, "L": 0, "V": 0, "N": 0}
    for f in findings:
        counter[f.kind] += 1
        idx = counter[f.kind]
        out.append(f"### {f.label(idx)} — {f.summary}")
        out.append("")
        locs = ", ".join(f"lines {s}-{e}" for s, e in f.locations if s > 0)
        if locs:
            out.append(f"- Locations: {locs}")
        out.append(f"- Proposed refactor: {f.refactor}")
        if f.saved_lines > 0:
            out.append(f"- Estimated saved: {f.saved_lines} lines")
        out.append("")

    # Detector 6 — unbound variables (INFO subsection, rendered separately)
    if unbound:
        out.append("## Detector 6 — unbound variables (INFO)")
        out.append("")
        out.append(
            "> INFO severity — passive, never blocks the exit code. "
            "Each entry names a `$VAR` referenced in a bash fence but never "
            "bound in-file. Add a guard or document who binds it."
        )
        out.append("")

    if spec_path:
        out.append(f"## Spec written")
        out.append("")
        out.append(f"A docs-lifecycle proposal spec has been written to:")
        out.append(f"  `{spec_path}`")
        out.append("")
        out.append("To land the cleanup:")
        slug = spec_path.stem.split("-", 3)[-1] if "-" in spec_path.stem else spec_path.stem
        out.append(f"  Run `Skill flow-dev` and reference spec slug `{slug}`.")
    elif spec_inline:
        out.append("## Spec preview (not written — review before committing)")
        out.append("")
        out.append("To write this spec to the host repo's `docs/specs/proposed/`, "
                   "re-run audit with `--write-spec`. Preview below — review for "
                   "accuracy, then decide to commit or discard.")
        out.append("")
        out.append("---")
        out.append("")
        out.append(spec_inline)
        out.append("")
        out.append("---")
        out.append("")
        out.append("Next step:")
        out.append("  - Re-run with `--write-spec` to commit this spec to "
                   "`<host>/docs/specs/proposed/<date>-<skill>-audit-cleanup.md`")
        out.append("  - Or pipe selected findings into a hand-crafted spec yourself")

    return "\n".join(out)


def render_spec(
    skill_name: str,
    target: Path,
    findings: list[Finding],
    date_str: str,
) -> str:
    """Render the docs-lifecycle proposal spec."""
    hi_med = [f for f in findings if f.severity in ("HIGH", "MED")]
    out = [
        "---",
        "kind: spec",
        "status: proposed",
        "---",
        "",
        f"# {skill_name} skill-audit cleanup",
        "",
        f"**Date**: {date_str}",
        f"**Source**: skill-audit run on `{target}`",
        f"**Findings to address**: {len(hi_med)} (HIGH + MED severity)",
        "",
        "## Background",
        "",
        f"skill-audit identified {len(findings)} total findings in `{target}`:",
        f"- {sum(1 for f in findings if f.severity == 'HIGH')} HIGH severity (must fix)",
        f"- {sum(1 for f in findings if f.severity == 'MED')} MED severity (should fix)",
        f"- {sum(1 for f in findings if f.severity == 'LOW')} LOW severity (optional)",
        f"- {sum(1 for f in findings if f.severity == 'INFO')} INFO (script-side hint)",
        "",
        "This spec covers the HIGH and MED findings as actionable tasks. "
        "LOW and INFO findings can be follow-ups.",
        "",
        "## Goals",
        "",
    ]

    if not hi_med:
        out.append("No HIGH or MED findings — no cleanup needed.")
        return "\n".join(out)

    for i, f in enumerate(hi_med, start=1):
        kind_label = "Redundancy" if f.kind == "R" else "Scriptifiable block"
        out.append(f"### Goal {i} ({f.severity}) — {kind_label}")
        out.append("")
        out.append(f"**Finding**: {f.summary}")
        locs = ", ".join(f"lines {s}-{e}" for s, e in f.locations if s > 0)
        if locs:
            out.append(f"**Locations**: {locs}")
        out.append(f"**Refactor**: {f.refactor}")
        out.append("")

    out.append("## Task contract")
    out.append("")
    out.append("Each goal above becomes one task. Tasks may be split further "
               "during `Skill flow-dev` Phase 1 decomposition.")
    out.append("")
    for i, f in enumerate(hi_med, start=1):
        out.append(f"- **Task {i}**: address {f.label(i)}")
        out.append(f"  - Acceptance: refactor applied, "
                   f"`lint-stop-prefixes.sh` still PASS (if any new script added).")
    out.append("")
    out.append("## Test plan")
    out.append("")
    out.append("- `lint-stop-prefixes.sh` PASS")
    out.append("- skill-audit re-run shows fewer HIGH/MED findings "
               "(this PR's specific findings are gone)")
    out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Main

def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    # Legacy positional + flags (UNCHANGED)
    ap.add_argument("target", nargs="?", help="Path to SKILL.md (single-skill mode)")
    ap.add_argument("--write-spec", action="store_true")
    ap.add_argument("--no-spec", action="store_true")

    # New advisory flags
    ap.add_argument("--metrics", action="store_true",
                    help="Advisory mode: metrics only, no detectors, no LLM.")
    ap.add_argument("--with-llm", action="store_true",
                    help="Advisory mode: metrics + LLM dispatch (default for single-skill audit; redundant with bare invocation).")
    ap.add_argument("--no-llm", action="store_true",
                    help="Advisory mode: skip LLM dispatch, metrics only. Synonym of --metrics; preferred name going forward.")
    ap.add_argument("--json", action="store_true",
                    help="Advisory mode only: emit JSON instead of Markdown.")
    ap.add_argument("--llm-timeout", type=int, default=600,
                    help="LLM dispatch timeout (default 600s, range 60-3600).")
    ap.add_argument("--rank-all", metavar="DIR",
                    help="Advisory mode: rank every SKILL.md under DIR.")
    ap.add_argument("--top", type=int, default=1,
                    help="--rank-all: dispatch LLM on top-N (default 1; 0 = no LLM).")
    ap.add_argument("--skill-root", metavar="DIR",
                    help="Resolve path-links against DIR instead of the target's parent "
                         "directory. Use when auditing a references/*.md file so that "
                         "paths like scripts/foo.sh resolve against the TRUE skill root.")

    args = ap.parse_args(argv)

    # Validate flag interactions per spec section "CLI surface".
    # --metrics is a synonym of --no-llm; both suppress LLM in advisory mode.
    advisory_flag_set = (args.metrics or args.with_llm or args.no_llm
                        or args.rank_all is not None or args.json)
    legacy_spec_flag_set = (args.write_spec or args.no_spec)
    if advisory_flag_set and legacy_spec_flag_set:
        print("audit: --metrics / --no-llm / --with-llm / --rank-all / --json are "
              "mutually exclusive with --write-spec / --no-spec", file=sys.stderr)
        return 1

    if args.metrics and args.no_llm:
        # Redundant but not harmful — they're synonyms. Accept silently.
        pass
    if args.with_llm and (args.metrics or args.no_llm):
        print("audit: --with-llm conflicts with --metrics / --no-llm "
              "(LLM cannot be both requested and suppressed)", file=sys.stderr)
        return 1

    if args.json and not (args.metrics or args.no_llm or args.with_llm
                          or args.rank_all is not None):
        print("audit: --json requires --metrics, --no-llm, --with-llm, or --rank-all",
              file=sys.stderr)
        return 1

    # Routing: legacy mode is opt-in via --write-spec / --no-spec. Bare
    # single-skill invocation goes through advisory mode (LLM by default).
    # See PR #501 — this is the post-#500 strangler step: advisory is the
    # default surface for single-skill audit; legacy detectors remain reachable
    # via explicit spec flags for the "audit + write spec" workflow.
    if legacy_spec_flag_set:
        return _run_legacy(args)
    return _run_advisory(args)


def _run_legacy(args) -> int:
    # Body of the pre-Task-8 main(). UNCHANGED in semantics.
    if not args.target:
        print("audit: target required for legacy mode", file=sys.stderr)
        return 1
    target = Path(args.target).resolve()
    if not target.is_file():
        print(f"audit: target not found: {target}", file=sys.stderr)
        return 1

    content = target.read_text()
    lines = content.splitlines()
    skill_dir = target.parent
    skill_name = skill_dir.name
    scripts_dir = skill_dir / "scripts"

    # --skill-root overrides the root used for path-link resolution so that
    # references/*.md files can resolve scripts/ paths against the true skill root.
    skill_root = Path(args.skill_root).resolve() if getattr(args, "skill_root", None) else None

    # Parse + detect
    blocks = parse_code_blocks(lines)
    # Task 1.A: build a shared parsed_context dict for new detectors (spec R9 #1).
    # Existing detectors keep their original signatures (no retrofit per spec L65).
    parsed_context = _build_parsed_context(content, lines=lines, code_blocks=blocks)
    findings = (
        detect_redundant_blocks(blocks)
        + detect_redundant_prose(content)
        + detect_scriptifiable_blocks(blocks)
        + (detect_script_side_redundancy(scripts_dir) if scripts_dir.is_dir() else [])
        + detect_frontmatter_pathology(target, parsed_context)
        + (detect_openai_yaml_consistency(skill_dir, parsed_context)
           if target.name == "SKILL.md" else [])
        + detect_broken_links(target, parsed_context, skill_root=skill_root)
        + detect_unbound_vars(blocks, skill_dir, scripts_dir)
    )

    # ADR 0005: project the navigability metric into a passive INFO finding so
    # the holistic composer (which runs the legacy detector) surfaces it.
    # Navigability is a SKILL.md-level metric, so only project for the SKILL.md
    # target — never for a references/*.md target. Lazy import keeps the
    # advisory cost off the pure-detector path.
    if target.name == "SKILL.md":
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from advisory import metrics as M  # noqa: E402
        nav = M.compute_navigability(target)
        nav_finding = project_metric_finding(
            score=nav.score,
            threshold=NAV_PROJECT_THRESHOLD,
            kind="N",
            severity="INFO",
            summary=(
                f"navigability: {nav.ordinal_ids} ordinal IDs, "
                f"{nav.mode_notes} mode notes, no SSOT map → consider "
                "PR830-style consolidation (collapse phase IDs, add a mode×phase "
                "SSOT table)"
            ),
            refactor="collapse phase IDs, add a mode×phase SSOT table",
        )
        if nav_finding is not None:
            findings.append(nav_finding)

    # Sort: HIGH first, then by line number. "V" (INFO) sorts after INFO.
    sev_rank = {"HIGH": 0, "MED": 1, "LOW": 2, "INFO": 3}
    findings.sort(key=lambda f: (sev_rank[f.severity], f.locations[0][0] if f.locations else 0))

    # Resolve spec output
    spec_path: Optional[Path] = None
    spec_content: Optional[str] = None
    host_root: Optional[Path] = None
    if not args.no_spec and findings:
        today = date.today().isoformat()
        spec_content = render_spec(skill_name, target, findings, today)
        host_root = find_docs_lifecycle_root(target)
        if args.write_spec and host_root:
            cfg = load_lifecycle_config(host_root)
            proposed_rel = cfg["specs"]["proposed"]
            spec_name = f"{today}-{skill_name}-audit-cleanup.md"
            spec_path = host_root / proposed_rel / spec_name
            spec_path.parent.mkdir(parents=True, exist_ok=True)
            spec_path.write_text(spec_content)

    # Render + emit report
    report = render_report(
        target, skill_name, len(lines),
        scripts_dir if scripts_dir.is_dir() else None,
        findings, spec_path,
        spec_inline=spec_content if not args.write_spec else None,
        host_root=host_root,
    )
    print(report)

    # PASSIVE kinds (I = script-side info, V = unbound var, N = projected
    # navigability metric — ADR 0005) must never flip the exit code. Only
    # non-passive findings determine 0 vs 2.
    if not [f for f in findings if f.kind not in ("I", "V", "N")]:
        return 2
    return 0


def _make_spawn():
    """Returns None — LLM dispatch is now the main agent's responsibility
    (see SKILL.md ## LLM advisory step). Tests inject a stub.

    _run_advisory() checks for a None return and skips LLM dispatch
    gracefully, emitting a stderr note 'LLM dispatch deferred to main agent'
    and falling back to metrics-only output.
    """
    return None


def _metrics_brief(size, imbalance, staleness, navigability, hints, scripts_dir) -> str:
    lines = [
        f"size: {size.lines_total} lines, {size.fenced_blocks} fenced blocks (score {size.score:.0f})",
        f"imbalance: {imbalance.substantive_blocks} substantive blocks / {imbalance.scripts_count} scripts (score {imbalance.score:.0f})",
        f"staleness: {staleness.last_modified_days} days, {staleness.meaningful_edits_90d} edits in 90d (score {staleness.score:.0f})",
        f"navigability: {navigability.ordinal_ids} ordinal IDs, {navigability.mode_notes} mode notes, span {navigability.line_span} (score {navigability.score:.0f})",
    ]
    if scripts_dir and Path(scripts_dir).is_dir():
        scripts = sorted(p.name for p in Path(scripts_dir).iterdir() if p.is_file())
        lines.append(f"scripts/: {', '.join(scripts) if scripts else '(empty)'}")
    if hints.phrases:
        lines.append("cross-section hints:")
        for p in hints.phrases[:10]:
            lines.append(f"  - {p['phrase']} → {', '.join(p['sections'])}")
    return "\n".join(lines)


def _run_advisory(args) -> int:
    # Import advisory modules lazily so legacy mode doesn't pay the cost.
    # Note: this file lives at skill-audit/scripts/syntax_audit.py, so
    # `from advisory import ...` works because scripts/ is on sys.path
    # when audit.py is invoked via `python3 audit.py`.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from advisory import metrics as M
    from advisory import ranker as R
    from advisory import llm_dispatch as L
    from advisory import report as RP

    THRESHOLD = 30

    if args.rank_all is not None:
        return _run_rank_all(args, M, R, L, RP, THRESHOLD)

    # Single-skill advisory
    if not args.target:
        print("audit: advisory mode requires <path-to-SKILL.md>", file=sys.stderr)
        return 1
    target = Path(args.target).resolve()
    if not target.is_file():
        print(f"audit: target not found: {target}", file=sys.stderr)
        return 1

    skill_dir = target.parent
    scripts_dir = skill_dir / "scripts"
    size = M.compute_size(target)
    imbalance = M.compute_imbalance(target, scripts_dir if scripts_dir.is_dir() else None)
    staleness = M.compute_staleness(target)
    navigability = M.compute_navigability(target)
    hints = M.compute_cross_section_hints(target)
    composite = R.composite_score(R.MetricInputs(
        size_score=size.score, imbalance_score=imbalance.score,
        staleness_score=staleness.score, navigability_score=navigability.score))

    # LLM dispatch policy (PR #501):
    #   - --with-llm:             explicit, dispatch LLM
    #   - --no-llm / --metrics:   explicit, skip LLM
    #   - bare invocation:        dispatch LLM (single-skill default)
    suppress_llm = args.no_llm or args.metrics
    want_llm = args.with_llm or not suppress_llm

    llm_result = None
    harness_fallback = False
    if want_llm:
        spawn = _make_spawn()
        if spawn is None:
            # LLM dispatch deferred to main agent (see SKILL.md ## LLM advisory
            # step). Skip dispatch gracefully; fall back to metrics-only output.
            print("audit: LLM dispatch deferred to main agent, "
                  "falling back to metrics-only output", file=sys.stderr)
            harness_fallback = True
        else:
            brief = _metrics_brief(size, imbalance, staleness, navigability, hints, scripts_dir)
            llm_result = L.dispatch_llm_audit(target, metrics_brief=brief, spawn=spawn)
            if llm_result.status != L.LLMStatus.OK:
                # Other dispatch failure (parse fail, generic spawn fail, etc.) —
                # surface in report and exit 1, matching the pre-#501 contract for
                # explicit --with-llm. Bare invocation hitting a real LLM failure
                # is treated as exit 1; the user asked for the default which means
                # LLM, and the LLM substantively failed.
                inp = RP.ReportInput(
                    target=target, mode="metrics-with-llm",
                    size=size, imbalance=imbalance, staleness=staleness,
                    navigability=navigability, hints=hints,
                    composite=composite, threshold=THRESHOLD,
                    llm_result=llm_result,
                )
                print(RP.render_json(inp) if args.json else RP.render_markdown(inp))
                return 1

    if llm_result is not None:
        mode = "metrics-with-llm"
    elif harness_fallback:
        mode = "metrics-llm-fallback"
    else:
        mode = "metrics"
    inp = RP.ReportInput(
        target=target,
        mode=mode,
        size=size, imbalance=imbalance, staleness=staleness,
        navigability=navigability, hints=hints,
        composite=composite, threshold=THRESHOLD,
        llm_result=llm_result,
    )
    print(RP.render_json(inp) if args.json else RP.render_markdown(inp))
    return 0 if composite >= THRESHOLD else 2


def _run_rank_all(args, M, R, L, RP, threshold) -> int:
    root = Path(args.rank_all).resolve()
    skill_mds = sorted(root.glob("*/SKILL.md"))
    if not skill_mds:
        print(f"audit: no SKILL.md found under {root}", file=sys.stderr)
        return 1

    ranked: list = []
    metrics_cache: dict = {}
    for skill in skill_mds:
        sz = M.compute_size(skill)
        ib = M.compute_imbalance(skill, (skill.parent / "scripts") if (skill.parent / "scripts").is_dir() else None)
        st = M.compute_staleness(skill)
        nv = M.compute_navigability(skill)
        hi = M.compute_cross_section_hints(skill)
        cm = R.composite_score(R.MetricInputs(sz.score, ib.score, st.score, nv.score))
        ranked.append(R.RankedSkill(
            name=skill.parent.name, composite=cm,
            size=sz.score, imbalance=ib.score, staleness=st.score,
            navigability=nv.score))
        metrics_cache[skill.parent.name] = (skill, sz, ib, st, nv, hi)
    ranked = R.rank_skills(ranked)

    failed: list = []
    top_llm: dict = {}
    if args.with_llm and args.top > 0:
        spawn = _make_spawn()
        if spawn is None:
            # LLM dispatch deferred to main agent — skip silently in rank-all mode.
            print("audit: LLM dispatch deferred to main agent; "
                  "skipping --with-llm dispatch in --rank-all", file=sys.stderr)
        else:
            for r in ranked[:args.top]:
                sk, sz, ib, st, nv, hi = metrics_cache[r.name]
                brief = _metrics_brief(sz, ib, st, nv, hi, sk.parent / "scripts")
                res = L.dispatch_llm_audit(sk, metrics_brief=brief, spawn=spawn)
                top_llm[r.name] = res
                if res.status != L.LLMStatus.OK:
                    failed.append((r.name, res.status.value))

    # Render the top-ranked skill's report as the main output, with full ranking appended.
    first = ranked[0]
    sk, sz, ib, st, nv, hi = metrics_cache[first.name]
    inp = RP.ReportInput(
        target=sk, skill_name=first.name,
        mode="rank-all",
        size=sz, imbalance=ib, staleness=st, navigability=nv, hints=hi,
        composite=first.composite, threshold=threshold,
        llm_result=top_llm.get(first.name),
        ranking=ranked, failed_dispatches=failed,
    )
    print(RP.render_json(inp) if args.json else RP.render_markdown(inp))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
