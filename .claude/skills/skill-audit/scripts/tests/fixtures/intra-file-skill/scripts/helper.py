"""Non-live helper module — never imported/invoked from SKILL.md, so the
liveness BFS marks it dead. It mirrors skill-audit's audit_finding.py: a private
helper called ONLY by a sibling function in the SAME file (bare unqualified
call), plus a truly-dead function with no caller anywhere.
"""


def _section(text):
    """Called only intra-file by parse() below — must NOT be zero-reader."""
    return [ln for ln in text.splitlines() if ln.strip()]


def parse(text):
    """Sibling caller of _section, in the same file."""
    return _section(text)


def orphan():
    """No caller anywhere — genuinely dead, must STAY zero-reader."""
    return 0
