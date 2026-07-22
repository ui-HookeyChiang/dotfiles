#!/usr/bin/env python3
"""skill-semantic-audit — Python entry point.

CLI mirrors the SKILL.md argument-hint:
    <path-to-SKILL.md> [--cross <dir>] [--axis G1|G8|IRD|all]
                       [--no-llm]

Exit codes (SKILL.md L91-99, mirrors ``skill-syntax-audit`` advisory-mode contract):
    0 = flagged for review (>= 1 finding emitted)
    2 = clean (all axes ran cleanly, zero findings)
    1 = tool/LLM failure (RuntimeError, dispatch failure, ValueError,
        ``--axis G7`` invocation, or input not found)

LLM dispatch is performed by the main agent per SKILL.md ## LLM advisory step.
This script emits metrics + rule findings (Python deterministic) only.
By default ``_resolve_llm_dispatch()`` returns ``None`` — G1 falls back to
its metrics-only path and G8's ``llm_fn`` is also ``None``.  The env var
``SKILL_SEMANTIC_AUDIT_LLM_DISPATCH`` is retained as an opt-in fallback for
legacy tests that inject a Python callable.

G7 paragraph density was removed in 2026-05-29 (spec
``docs/specs/archive/2026-05-29-prose-guidelines-g7-dedup.md``); paragraph-density
detection now lives in `prose-guidelines`.  ``--axis G7`` is intercepted before
argparse and exits 1 with a redirect message.

Tech debt — G8/G1 detector signature divergence:
    * G1.detect(paths, *, no_llm=False, llm_dispatch=callable|None,
                corpus_dir=str|None)
    * G8.detect(paths, *, no_llm=False, llm_fn=callable|None)
``audit.py`` translates the single user-facing ``llm_dispatch`` callable into
``llm_fn=`` when calling G8.  We deliberately keep the divergent kwarg names
inside the detectors (per CONTEXT — detector internals are frozen) and absorb
the inconsistency here.  Unifying the kwarg name across detectors is recorded
as follow-up tech debt.
"""
from __future__ import annotations

import argparse
import importlib
import os
import sys
from pathlib import Path
from typing import Any, Callable, Optional

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from detectors import (  # noqa: E402  (sys.path manipulation above is intentional)
    g1_cross_skill_dup,
    g8_progressive_disclosure,
    inline_reasoning_dup,
)

AXES = ("G1", "G8", "IRD")
_AXIS_CHOICES = AXES + ("all",)

_G7_REMOVED_MESSAGE = (
    "Error: G7 axis was removed in 2026-05-29 "
    "(see docs/specs/archive/2026-05-29-prose-guidelines-g7-dedup.md).\n"
    "Paragraph-density detection now lives in `prose-guidelines`:\n"
    "\n"
    "  Skill prose-guidelines <path>/SKILL.md\n"
    "\n"
    "prose-guidelines inherits G7's prompt verbatim and adds "
    "lexical/meta/hedge classes.\n"
)

EXIT_FLAGGED = 0
EXIT_CLEAN = 2
EXIT_FAILURE = 1

_ENV_LLM_DISPATCH = "SKILL_SEMANTIC_AUDIT_LLM_DISPATCH"


def _normalise_axis(value: str) -> str:
    """argparse type=: uppercase G1/G8 but lowercase 'all' (axis aliases).

    Without this, ``--axis all`` becomes ``ALL`` and fails the ``choices``
    check (choices use lowercase ``all`` to match the sentinel checked by
    ``_axes_to_run``).
    """
    v = (value or "").strip()
    if v.lower() == "all":
        return "all"
    return v.upper()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="audit.py",
        description=(
            "skill-semantic-audit — finding-level semantic cleanup "
            "(G1 cross-skill duplication, G8 progressive disclosure, "
            "IRD inline-reasoning-duplication)."
        ),
    )
    parser.add_argument("skill_md", metavar="<path-to-SKILL.md>",
                        help="target SKILL.md to audit")
    parser.add_argument("--cross", metavar="<dir>", default=None,
                        help="directory of skills for G1 cross-skill comparison")
    parser.add_argument("--axis", type=_normalise_axis, choices=_AXIS_CHOICES,
                        default=None,
                        help="restrict to a single axis "
                             "(default / 'all': run G1+G8+IRD)")
    parser.add_argument("--no-llm", action="store_true",
                        help="skip LLM dispatch; detectors return metrics-only "
                             "(or [] for axes requiring LLM)")
    return parser


def _yaml_scalar(value: Any, key_indent: int = 4) -> str:
    """Emit a scalar as YAML.  Handles bool / int / float / None / str.

    ``key_indent`` is the column (0-indexed) at which the key for this value
    sits.  Literal block scalars (``|``) require the body to be indented
    STRICTLY deeper than the key per YAML 1.2; we use ``key_indent + 2``.
    Default of 4 preserves the legacy 6-space body offset for callers that
    don't pass the parameter.

    Source of truth for the findings: stdout YAML scalar emitter.
    Used by _render_finding_yaml.
    """
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if not isinstance(value, str):
        value = str(value)
    # Use a block-style or quoted scalar depending on contents.
    needs_quote = any(c in value for c in [":", "#", "\n", "'", '"', "{", "}", "[", "]", ",", "&", "*", "?", "|", "<", ">", "=", "!", "%", "@", "`"])
    if not value:
        return "''"
    if "\n" in value:
        # Use literal block scalar.  Body must be indented deeper than the key.
        body_indent = " " * (key_indent + 2)
        lines = value.rstrip("\n").split("\n")
        return "|\n" + "\n".join(f"{body_indent}{ln}" for ln in lines)
    if needs_quote:
        escaped = value.replace('"', '\\"')
        return f'"{escaped}"'
    return value


def _render_finding_yaml(finding: dict, base_indent: int = 4) -> str:
    """Render a single finding dict as a YAML list item under ``findings:``.

    Source of truth for the findings: stdout YAML list-item emitter.
    Signature ``(finding: dict, base_indent: int = 4) -> str`` is part of the
    public contract; changing it breaks byte-level regression tests.

    Order matches finding-schema.md L7-19.  ``numeric_basis`` is rendered as a
    nested mapping for G7 and as ``null`` for G1/G8.
    """
    pad = " " * base_indent
    out: list[str] = []
    # "- id:" sits at base_indent; key column is base_indent.
    out.append(f"{pad}- id: {_yaml_scalar(finding.get('id', ''), key_indent=base_indent)}")
    inner = " " * (base_indent + 2)
    for key in ("axis", "severity", "confidence", "title", "summary"):
        if key in finding:
            out.append(f"{inner}{key}: {_yaml_scalar(finding[key], key_indent=base_indent + 2)}")
    # locations: list of {file, lines}
    locs = finding.get("locations") or []
    out.append(f"{inner}locations:")
    if not locs:
        out[-1] = f"{inner}locations: []"
    else:
        for loc in locs:
            # nested list entries: "- file:" sits at inner+2, key column = base_indent+4.
            out.append(f"{inner}  - file: {_yaml_scalar(loc.get('file', ''), key_indent=base_indent + 4)}")
            out.append(f"{inner}    lines: {_yaml_scalar(loc.get('lines', ''), key_indent=base_indent + 4)}")
    if "evidence_quote" in finding:
        out.append(f"{inner}evidence_quote: {_yaml_scalar(finding['evidence_quote'], key_indent=base_indent + 2)}")
    # numeric_basis: dict if detector populated it, null otherwise.
    nb = finding.get("numeric_basis")
    if isinstance(nb, dict):
        out.append(f"{inner}numeric_basis:")
        for k, v in nb.items():
            # nested mapping values: key sits at inner+2, key column = base_indent+4.
            out.append(f"{inner}  {k}: {_yaml_scalar(v, key_indent=base_indent + 4)}")
    else:
        out.append(f"{inner}numeric_basis: null")
    if "suggested_action" in finding:
        out.append(f"{inner}suggested_action: {_yaml_scalar(finding['suggested_action'], key_indent=base_indent + 2)}")
    out.append(f"{inner}requires_human: {_yaml_scalar(bool(finding.get('requires_human', True)), key_indent=base_indent + 2)}")
    return "\n".join(out)


def _resolve_llm_dispatch() -> Optional[Callable[..., Any]]:
    """By default returns None — main agent dispatches LLM via Agent tool spawn
    per SKILL.md ## LLM advisory step.

    Env var ``SKILL_SEMANTIC_AUDIT_LLM_DISPATCH`` is retained as an opt-in
    fallback for legacy tests that inject a Python callable.  Format:
    ``module.path:callable_name`` (preferred) or ``module.path.callable_name``.
    Returns ``None`` when the env var is unset, empty, or unresolvable; emits
    a stderr warning on resolution failure but does NOT raise.
    """
    spec_str = os.environ.get(_ENV_LLM_DISPATCH, "").strip()
    if not spec_str:
        return None
    if ":" in spec_str:
        module_path, _, attr = spec_str.partition(":")
    else:
        module_path, _, attr = spec_str.rpartition(".")
    if not module_path or not attr:
        print(
            f"audit.py: ignoring {_ENV_LLM_DISPATCH}={spec_str!r} — "
            "expected 'module.path:callable' format",
            file=sys.stderr,
        )
        return None
    try:
        module = importlib.import_module(module_path)
        fn = getattr(module, attr)
    except (ImportError, AttributeError) as exc:
        print(
            f"audit.py: failed to resolve {_ENV_LLM_DISPATCH}={spec_str!r} "
            f"({exc!r}); falling back to no-LLM",
            file=sys.stderr,
        )
        return None
    if not callable(fn):
        print(
            f"audit.py: {_ENV_LLM_DISPATCH}={spec_str!r} resolved to a "
            "non-callable; falling back to no-LLM",
            file=sys.stderr,
        )
        return None
    return fn


def _dispatch(
    axis: str,
    skill_md: str,
    cross: str | None,
    no_llm: bool,
    llm_dispatch: Optional[Callable[..., Any]],
) -> list[dict]:
    """Call the named detector with axis-appropriate kwargs.

    The detector layer's kwarg names diverge by design (see module docstring
    — G1 uses ``llm_dispatch=``, G8 uses ``llm_fn=``).  This function
    absorbs the divergence so the rest of audit.py reasons about a single
    user-facing dispatch callable.
    """
    if axis == "G1":
        return g1_cross_skill_dup.detect(
            [skill_md],
            no_llm=no_llm,
            corpus_dir=cross,
            llm_dispatch=llm_dispatch,
        )
    if axis == "G8":
        return g8_progressive_disclosure.detect(
            [skill_md],
            no_llm=no_llm,
            llm_fn=llm_dispatch,
        )
    if axis == "IRD":
        return inline_reasoning_dup.detect(
            [skill_md],
            no_llm=no_llm,
            corpus_dir=cross,
        )
    raise ValueError(f"unknown axis: {axis}")  # pragma: no cover


def _axes_to_run(axis_flag: str | None) -> tuple[str, ...]:
    if axis_flag in (None, "all"):
        return AXES
    return (axis_flag,)


def _intercept_removed_g7_axis(argv: list[str] | None) -> None:
    """If the user passed ``--axis G7`` (any case), print the redirect
    message to stderr and ``sys.exit(1)`` before argparse runs.

    Argparse would otherwise reject G7 with its own "invalid choice" error,
    losing the redirect message that points users at ``prose-guidelines``.
    Spec: docs/specs/archive/2026-05-29-prose-guidelines-g7-dedup.md.
    """
    if not argv:
        return
    for i, tok in enumerate(argv):
        if tok == "--axis" and i + 1 < len(argv):
            if argv[i + 1].strip().upper() == "G7":
                sys.stderr.write(_G7_REMOVED_MESSAGE)
                sys.exit(1)
        elif tok.startswith("--axis="):
            if tok.split("=", 1)[1].strip().upper() == "G7":
                sys.stderr.write(_G7_REMOVED_MESSAGE)
                sys.exit(1)


def main(argv: list[str] | None = None) -> int:
    _intercept_removed_g7_axis(argv if argv is not None else sys.argv[1:])
    args = _build_parser().parse_args(argv)

    # Directory-argument guard: auto-resolve dir → dir/SKILL.md
    skill_path = Path(args.skill_md)
    if skill_path.is_dir():
        candidate = skill_path / "SKILL.md"
        if candidate.is_file():
            print(f"note: '{skill_path}' is a directory, using '{candidate}'", file=sys.stderr)
            args.skill_md = str(candidate)
        else:
            print(f"error: '{skill_path}' is a directory and '{candidate}' does not exist", file=sys.stderr)
            return EXIT_FAILURE

    if not os.path.exists(args.skill_md):
        print(f"audit.py: input not found: {args.skill_md}", file=sys.stderr)
        return EXIT_FAILURE

    llm_dispatch = _resolve_llm_dispatch()
    aggregated: list[dict] = []

    for axis in _axes_to_run(args.axis):
        try:
            findings = _dispatch(
                axis, args.skill_md, args.cross,
                no_llm=args.no_llm, llm_dispatch=llm_dispatch,
            )
        except g1_cross_skill_dup.G1InsufficientContentError:
            # G1 had < 2 candidate paragraphs — an advisory N/A "not enough
            # qualifying content to analyze" condition (short SKILL.md / short
            # reference file). This is NOT a tool failure: skip G1 and CONTINUE
            # to the next axis (e.g. G8) so coverage is not silently lost. The
            # hint still prints. (A `return` here would skip every later axis —
            # the HIGH coverage hole code-review caught.) If the whole loop
            # finishes with zero real findings, main() returns EXIT_CLEAN below.
            print(
                "audit.py: G1 found fewer than 2 candidate paragraphs "
                f"(>= {g1_cross_skill_dup.MIN_CANDIDATE_WORDS} words each). "
                "Pass `--cross <dir>` to add more files, or check that the "
                "target SKILL.md contains qualifying prose paragraphs.",
                file=sys.stderr,
            )
            continue
        except ValueError as exc:
            # A plain ValueError (e.g. corpus_dir not a directory) is a genuine
            # bad-arg error — keep EXIT_FAILURE.
            print(f"audit.py: {exc}", file=sys.stderr)
            return EXIT_FAILURE
        except NotImplementedError as exc:
            # Stub detector still in place (Tasks 13/14 not yet merged into
            # this lineage).  Treat as dispatch failure -> exit 1.
            # NB: NotImplementedError is a subclass of RuntimeError; this
            # branch MUST precede the RuntimeError handler below.
            print(
                f"audit.py: {axis} detector not implemented ({exc}); "
                "treat as dispatch failure.",
                file=sys.stderr,
            )
            return EXIT_FAILURE
        except RuntimeError as exc:
            # Anti-hallucination drop limit hit, or detector signalled
            # untrustworthy run.  Per finding-schema.md L35 + SKILL.md L99.
            print(
                f"audit.py: {axis} detector raised RuntimeError ({exc}); "
                "run aborted as untrustworthy.",
                file=sys.stderr,
            )
            return EXIT_FAILURE
        if not isinstance(findings, list):
            print(
                f"audit.py: {axis} detector returned non-list "
                f"({type(findings).__name__}); treating as failure.",
                file=sys.stderr,
            )
            return EXIT_FAILURE
        aggregated.extend(findings)

    # Split N/A advisories from real findings.  N/A advisories carry
    # ``not_applicable: True`` (emitted by detectors for open-concept axes
    # under --no-llm — §6 case-3).  Under --no-llm they are surfaced in the
    # findings block as confirm-candidates (spec determinism-mismatch rule)
    # so the deterministic side does not silently hide open-concept axes.
    # A stderr notice is still emitted for caller visibility.
    na_advisories = [f for f in aggregated if f.get("not_applicable")]
    real_findings = [f for f in aggregated if not f.get("not_applicable")]

    for na in na_advisories:
        print(
            f"audit.py: NOT_APPLICABLE [{na.get('axis', '?')}] "
            f"{na.get('summary', na.get('title', ''))}",
            file=sys.stderr,
        )

    # Emit findings as YAML to stdout (top-level ``findings:`` key per
    # finding-schema.md L3).  Minimal renderer (see _render_finding_yaml).
    print("findings:")
    for f in real_findings:
        print(_render_finding_yaml(f))
    # Open-concept axes under --no-llm: surface as confirm-candidates (spec
    # determinism-mismatch rule), not stderr-only NOT_APPLICABLE.  Indent to
    # match _render_finding_yaml (dash col 4, keys col 6) so a mixed
    # findings: block stays valid YAML; scalars routed through _yaml_scalar.
    for na in na_advisories:
        print(f"    - axis: {_yaml_scalar(na.get('axis', '?'), key_indent=6)}")
        print(f"      needs_probabilistic_confirm: true")
        summary = na.get("summary", "(open-concept axis; LLM verdict required)")
        print(f"      summary: {_yaml_scalar(summary, key_indent=6)}")

    return EXIT_FLAGGED if real_findings else EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main())
