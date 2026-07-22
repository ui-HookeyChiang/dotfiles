"""skill-semantic-audit detector package.

Re-exports the axis detectors so callers can do:

    from detectors import g1_cross_skill_dup, g8_progressive_disclosure
    from detectors import inline_reasoning_dup

G7 (paragraph density) was removed in 2026-05-29 — paragraph-density
detection now lives in `prose-guidelines`.  See spec
``docs/specs/archive/2026-05-29-prose-guidelines-g7-dedup.md``.
"""
from . import g1_cross_skill_dup, g8_progressive_disclosure, inline_reasoning_dup

__all__ = [
    "g1_cross_skill_dup",
    "g8_progressive_disclosure",
    "inline_reasoning_dup",
]
