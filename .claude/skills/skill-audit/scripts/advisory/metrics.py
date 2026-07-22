"""Advisory mode metrics: M1 size, M2 imbalance, M3 staleness, M4 hints.

Pure functions over filesystem inputs. No mutation. No I/O beyond reads
(except M3 which shells out to git log).
"""
from __future__ import annotations

import math
import re
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path


FENCE_RE = re.compile(r"^```")
INS_DEL_RE = re.compile(r'(\d+) insertion[s]?\(\+\)|(\d+) deletion[s]?\(-\)')


def _strip_frontmatter(text: str) -> str:
    """Return text with YAML frontmatter removed if present.

    Frontmatter is detected only when text starts with '---\\n' at byte 0,
    and a closing line of exactly '---' (possibly with trailing newline)
    is found. If either condition fails, returns text unchanged.

    This is intentionally conservative — only the strict single-document
    frontmatter pattern documented in markdown-with-YAML conventions.
    """
    if not text.startswith("---\n"):
        return text
    # Find closing --- on its own line
    rest = text[4:]  # skip the opening "---\n"
    idx = rest.find("\n---\n")
    if idx < 0:
        # check trailing case: file ends with "---" without trailing newline
        if rest.endswith("\n---"):
            return ""
        return text
    return rest[idx + len("\n---\n"):]


@dataclass
class SizeMetric:
    lines_total: int
    lines_prose: int
    bytes_total: int
    fenced_blocks: int
    score: float


def compute_size(skill_md: Path) -> SizeMetric:
    text = _strip_frontmatter(skill_md.read_text())
    lines = text.splitlines()
    lines_total = len(lines)
    bytes_total = len(text.encode())

    in_fence = False
    fenced_blocks = 0
    fenced_lines = 0
    for ln in lines:
        if FENCE_RE.match(ln):
            if in_fence:
                in_fence = False
            else:
                in_fence = True
                fenced_blocks += 1
            fenced_lines += 1
            continue
        if in_fence:
            fenced_lines += 1

    lines_prose = lines_total - fenced_lines

    if lines_total < 200:
        score = 0.0
    else:
        score = min(100.0, math.log(lines_total / 200) * 30)

    return SizeMetric(
        lines_total=lines_total,
        lines_prose=lines_prose,
        bytes_total=bytes_total,
        fenced_blocks=fenced_blocks,
        score=score,
    )


COMMENT_RE = re.compile(r"^\s*#")
BLANK_RE = re.compile(r"^\s*$")


@dataclass
class ImbalanceMetric:
    substantive_blocks: int
    scripts_count: int
    imbalance_ratio: float
    score: float


def compute_imbalance(skill_md: Path, scripts_dir: Path | None) -> ImbalanceMetric:
    text = _strip_frontmatter(skill_md.read_text())
    lines = text.splitlines()

    substantive = 0
    in_fence = False
    block_buf: list[str] = []
    for ln in lines:
        if FENCE_RE.match(ln):
            if in_fence:
                in_fence = False
                non_comment_non_blank = sum(
                    1 for b in block_buf
                    if not COMMENT_RE.match(b) and not BLANK_RE.match(b)
                )
                if non_comment_non_blank >= 3:
                    substantive += 1
                block_buf = []
            else:
                in_fence = True
            continue
        if in_fence:
            block_buf.append(ln)

    scripts_count = 0
    if scripts_dir is not None and scripts_dir.is_dir():
        for f in scripts_dir.iterdir():
            if f.is_file() and f.suffix in (".sh", ".bash", ".py"):
                scripts_count += 1
            # iterdir is non-recursive so tests/ subdir is naturally excluded

    if scripts_count == 0:
        score = min(60.0, substantive * 4.0)
        ratio = float(substantive)
    else:
        ratio = substantive / scripts_count
        score = min(100.0, ratio * 10)
    return ImbalanceMetric(
        substantive_blocks=substantive,
        scripts_count=scripts_count,
        imbalance_ratio=ratio,
        score=score,
    )


@dataclass
class StalenessMetric:
    last_modified_days: int  # -1 if not in git
    meaningful_edits_90d: int
    score: float


def compute_staleness(skill_md: Path) -> StalenessMetric:
    r = subprocess.run(
        ["git", "log", "-1", "--format=%ct", "--", str(skill_md)],
        capture_output=True, text=True,
        cwd=skill_md.parent,
    )
    if r.returncode != 0 or not r.stdout.strip():
        return StalenessMetric(last_modified_days=-1, meaningful_edits_90d=0, score=0.0)
    try:
        last_ct = int(r.stdout.strip())
    except ValueError:
        return StalenessMetric(last_modified_days=-1, meaningful_edits_90d=0, score=0.0)
    days = int((time.time() - last_ct) / 86400)

    r2 = subprocess.run(
        ["git", "log", "--since=90.days", "--shortstat", "--format=%H",
         "--", str(skill_md)],
        capture_output=True, text=True,
        cwd=skill_md.parent,
    )
    meaningful = 0
    if r2.returncode == 0:
        for ln in r2.stdout.splitlines():
            ins = dels = 0
            for m in INS_DEL_RE.finditer(ln):
                if m.group(1):
                    ins += int(m.group(1))
                if m.group(2):
                    dels += int(m.group(2))
            if ins + dels > 10:
                meaningful += 1

    score = min(100.0, days / 1.8) if days >= 0 else 0.0
    if meaningful > 0:
        score *= 0.5
    return StalenessMetric(
        last_modified_days=days,
        meaningful_edits_90d=meaningful,
        score=score,
    )


# M5 — navigability (count-based structural-navigation cost, in composite)
#
# A deterministic bloat signal for the navigation load a SKILL.md imposes:
# ordinal-ID sprawl (Phase N / Step N / lettered sub-steps / named gates /
# Amendment AN) plus scattered per-mode notes. No semantic judgement — every
# term is a count. Fence-aware: IDs inside code blocks are agent-irrelevant
# noise and are not counted.

# Ordinal-ID landmark patterns. Each match is one landmark an agent must hold.
_NAV_PHASE_RE = re.compile(r"\bphase\s+\d+\b", re.IGNORECASE)
_NAV_STEP_RE = re.compile(r"\bstep\s+\d+(?:\.\d+)?\b", re.IGNORECASE)
_NAV_SUBSTEP_RE = re.compile(r"\b\d+[a-f]\b")  # lettered sub-step e.g. 5a / 5b
_NAV_GATE_RE = re.compile(r"\bgate\b", re.IGNORECASE)
_NAV_AMENDMENT_RE = re.compile(r"\bamendment\s+A\d+\b", re.IGNORECASE)

# Per-mode-note branch patterns: "in X mode" inline branches and "under <ENV>".
_NAV_MODE_RE = re.compile(r"\bin\s+[\w-]+\s+mode\b", re.IGNORECASE)
_NAV_UNDER_ENV_RE = re.compile(r"\bunder\s+<[A-Za-z_]+>")


@dataclass
class NavigabilityMetric:
    ordinal_ids: int
    mode_notes: int
    line_span: int  # first..last line carrying a mode note (0 if <2 notes)
    score: float


def compute_navigability(skill_md: Path) -> NavigabilityMetric:
    """Count-based navigation-cost signal: ordinal-ID density + mode scatter.

    ordinal_ids — total Phase/Step/sub-step/gate/Amendment landmarks (prose +
    headings, code fences excluded). mode_notes — inline "in X mode" /
    "under <ENV>" branches; line_span is the line distance between the first
    and last such note (a wide span with no consolidating table is worse).
    Pure count — no semantic judgement enters score.
    """
    lines = _strip_frontmatter(skill_md.read_text()).splitlines()

    ordinal_ids = 0
    mode_notes = 0
    mode_lines: list[int] = []
    in_fence = False
    for idx, ln in enumerate(lines):
        if FENCE_RE.match(ln):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        ordinal_ids += len(_NAV_PHASE_RE.findall(ln))
        ordinal_ids += len(_NAV_STEP_RE.findall(ln))
        ordinal_ids += len(_NAV_SUBSTEP_RE.findall(ln))
        ordinal_ids += len(_NAV_GATE_RE.findall(ln))
        ordinal_ids += len(_NAV_AMENDMENT_RE.findall(ln))
        line_notes = len(_NAV_MODE_RE.findall(ln)) + len(_NAV_UNDER_ENV_RE.findall(ln))
        if line_notes:
            mode_notes += line_notes
            mode_lines.append(idx)

    line_span = (mode_lines[-1] - mode_lines[0]) if len(mode_lines) >= 2 else 0

    # ordinal_ids dominates (the PR #830 sprawl signal); mode scatter adds a
    # smaller bump scaled by how widely the branches are strewn. Log-saturating
    # so a dense workflow lands high without a single axis spiking past the cap.
    id_score = math.log1p(ordinal_ids) * 22 if ordinal_ids else 0.0
    span_factor = 1.0 + min(1.0, line_span / 200.0)
    mode_score = math.log1p(mode_notes) * 6 * span_factor if mode_notes else 0.0
    score = min(100.0, id_score + mode_score)

    return NavigabilityMetric(
        ordinal_ids=ordinal_ids,
        mode_notes=mode_notes,
        line_span=line_span,
        score=score,
    )


# M4 — cross-section hints (LLM prior, not in composite)
H2_H3_RE = re.compile(r"^(##|###)\s+(.+)$")
PHRASE_RE = re.compile(r"\b([A-Z][a-z]+(?:\s+[A-Za-z]+){1,2})\b")
TECHNICAL_TERMS = {
    "AWS DryRun", "docker exec", "git fetch", "git push", "Phase 1", "Phase 2",
    "SKILL md", "make PRODUCT", "pre-flight", "uicli authorize",
}


@dataclass
class CrossSectionHints:
    phrases: list[dict] = field(default_factory=list)  # [{phrase, sections}]


def compute_cross_section_hints(skill_md: Path) -> CrossSectionHints:
    lines = _strip_frontmatter(skill_md.read_text()).splitlines()
    current_section: str | None = None
    in_fence = False
    found: dict[str, set[str]] = {}

    for ln in lines:
        if FENCE_RE.match(ln):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = H2_H3_RE.match(ln)
        if m:
            current_section = m.group(2).strip()
            continue
        if current_section is None:
            continue
        for ph in PHRASE_RE.findall(ln):
            ph = ph.strip()
            if len(ph) < 5:
                continue
            found.setdefault(ph, set()).add(current_section)
        low = ln.lower()
        for t in TECHNICAL_TERMS:
            if t.lower() in low:
                found.setdefault(t, set()).add(current_section)

    phrases = [
        {"phrase": ph, "sections": sorted(secs)}
        for ph, secs in found.items()
        if len(secs) >= 3
    ]
    phrases.sort(key=lambda p: (-len(p["sections"]), p["phrase"]))
    return CrossSectionHints(phrases=phrases)
