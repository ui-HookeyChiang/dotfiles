"""Uniform finding row + per-engine output adapters for skill-audit.

Each engine emits its own native format; these adapters parse that PRESENTATION
output into a uniform AuditFinding row for the composed report. The rich
per-engine fields stay inside each engine — the boundary carries only what the
unified report renders.

The adapters guard engine stdout at the trust boundary: a malformed or empty
section yields an empty list rather than a crash.
"""
from __future__ import annotations

from dataclasses import dataclass
import re

import yaml

# deadcode reachability classes: a=live, b=test-only are NOT actionable.
_ACTIONABLE_DEADCODE = {"c", "d", "e", "f"}


@dataclass
class AuditFinding:
    engine: str
    code: str
    severity: str
    location: str
    message: str
    file: str = "SKILL.md"


def _section(stdout: str, header: str) -> list[str]:
    """Return non-blank lines under a '## <header>' H2, until the next H2.

    H3 (`### `) lines stay inside the section — only a real `## ` boundary ends
    it.
    """
    out: list[str] = []
    in_block = False
    for ln in stdout.splitlines():
        if ln.strip() == f"## {header}":
            in_block = True
            continue
        if in_block and ln.startswith("## ") and not ln.startswith("### "):
            break
        if in_block and ln.strip():
            out.append(ln)
    return out


def _strip_ticks(s: str) -> str:
    return s.strip().strip("`").strip()


def parse_deadcode(stdout: str, file: str = "SKILL.md") -> list[AuditFinding]:
    """Parse the `## Reachability findings` markdown table.

    Keeps only actionable classes (c/d/e/f); the KEEP / (b) rows are dropped.
    location = the `Where` cell (ticks stripped); message = the `Note` cell.

    Deadcode walks the whole skill dir, so each finding names its OWN target in
    the `Where` cell (e.g. ``references/bloated.md`` or ``scripts/x.sh:88``).
    finding.file is stamped from that target so aggregate() files the row under
    the right ``#### <file>`` section. ``file`` is the catch-all default when a
    row names no specific in-tree path.
    """
    out: list[AuditFinding] = []
    for ln in _section(stdout, "Reachability findings"):
        ln = ln.strip()
        if not ln.startswith("|") or ln.startswith("| Class") or set(ln) <= set("|-: "):
            continue  # skip the header + separator rows
        cells = [c.strip() for c in ln.strip("|").split("|")]
        if len(cells) < 6:
            continue
        m = re.match(r"\((?P<cls>[a-zA-Z]+)\)", cells[0])
        if not m or m.group("cls") not in _ACTIONABLE_DEADCODE:
            continue
        sev = cells[1] if cells[1] != "—" else "MED"
        location = _strip_ticks(cells[4])
        out.append(AuditFinding("deadcode", m.group("cls"), sev,
                                location, cells[5],
                                _deadcode_target_file(location, file)))
    return out


def _deadcode_target_file(location: str, default: str) -> str:
    """Map a deadcode `Where` cell to the file the finding is ABOUT.

    The cell names an in-tree path, optionally with a ``:line`` suffix
    (``scripts/x.sh:88``); strip the suffix and return the path. A bare token
    with no path separator (no in-tree file) falls back to ``default``.
    """
    path = location.split(":", 1)[0].strip()
    return path if "/" in path else default


def parse_syntax(stdout: str, file: str = "SKILL.md") -> list[AuditFinding]:
    """Parse the `## Findings` block from `audit.sh --no-spec`.

    Each finding is an H3 header followed by a `- Locations:` line:
        ### F1 (MED) — stale Skill ref: ...
        - Locations: lines 101-101
    """
    head = re.compile(
        r"^###\s*(?P<code>[A-Z]\d+)\s*\((?P<sev>HIGH|MED|LOW|INFO)\)\s*[—-]\s*(?P<msg>.*)$")
    out: list[AuditFinding] = []
    pending: AuditFinding | None = None
    for ln in _section(stdout, "Findings"):
        s = ln.strip()
        m = head.match(s)
        if m:
            pending = AuditFinding("syntax", m.group("code"), m.group("sev"),
                                   "—", m.group("msg").strip(), file)
            out.append(pending)
        elif pending and s.startswith("- Locations:"):
            pending.location = s.split("Locations:", 1)[1].strip()
            pending = None
    return out


_SEVERITY_LADDER = {"high": "HIGH", "medium": "MED", "med": "MED", "low": "LOW"}


def parse_semantic(stdout: str, file: str = "SKILL.md") -> list[AuditFinding]:
    """Parse the YAML `findings:` list emitted by `audit.py --no-llm`.

    The engine hand-renders valid YAML, so we parse it with yaml.safe_load
    rather than re-deriving the grammar. NOT_APPLICABLE notices land on stderr,
    so stdout is pure YAML; we still slice from the `findings:` key for safety.
    location = the first entry's `lines`; message = `title` (falling back to
    `summary`).
    """
    idx = stdout.find("findings:")
    if idx < 0:
        return []
    doc = yaml.safe_load(stdout[idx:]) or {}
    findings = doc.get("findings") or []
    out: list[AuditFinding] = []
    for f in findings:
        sev = _SEVERITY_LADDER.get(str(f.get("severity", "")).lower(), "MED")
        locs = f.get("locations") or []
        location = str(locs[0].get("lines", "—")) if locs else "—"
        message = f.get("title") or f.get("summary", "")
        out.append(AuditFinding("semantic", f.get("axis", "G?"), sev,
                                location, message, file))
    return out
