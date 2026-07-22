"""skill-audit — unified skill audit composer.

Runs the deterministic leg via scripts/run.sh (co-located), then emits a banner
for the 2 LLM legs (probabilistic, prose) that the main agent must dispatch.
Diagnostic-only: never writes, never mutates.

Usage: skill-audit.py <skill-dir>
"""
from __future__ import annotations
import subprocess, sys, pathlib


def run_engine(cmd: list[str]) -> tuple[str, int, str]:
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.stdout, p.returncode, p.stderr


def missing_legs_banner(legs_ran: set[str]) -> str | None:
    """Return a banner string naming the LLM legs NOT yet dispatched, or None when all ran.

    Pure helper — unit-testable without subprocess or filesystem.
    The script always calls it with an empty set (the composer cannot run LLM
    legs), so a bare run always names both as the not-yet-dispatched signal.
    The gate is the trace assert in skill-audit/SKILL.md §GATE, NOT this set.
    """
    required = {"probabilistic", "prose"}
    missing = sorted(required - legs_ran)
    if not missing:
        return None
    return (
        f"NOTE: dispatch the remaining LLM legs before reporting complete: "
        f"{', '.join(missing)}. Run the probabilistic leg (1 agent, "
        f"syntax 6-axes + semantic G1/G8) and prose-guidelines (SKILL.md > 200 lines)."
    )


def rollup_exit(engine_codes: list[int], any_error: bool) -> int:
    if any_error:
        return 1
    if any(c == 0 for c in engine_codes):  # engine exit 0 = problem-found
        return 0
    return 2


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print("usage: skill-audit.py <skill-dir>", file=sys.stderr)
        return 1
    skill_dir = pathlib.Path(argv[1])
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        print(f"skill-audit: no SKILL.md in {skill_dir}", file=sys.stderr)
        return 1

    codes: list[int] = []
    any_error = False

    # Deterministic half: co-located run.sh (was: skill-audit/scripts/run.sh).
    here = pathlib.Path(__file__).resolve().parent
    det_cmd = ["bash", str(here / "run.sh"), str(skill_dir)]
    det_out, det_rc, det_err = run_engine(det_cmd)
    # run.sh contract: 0=problem 2=clean 1=error. Any other code (e.g. 127,
    # script not found) is also a failure — treat anything outside {0,2} as error
    # and surface the engine's stderr so the reason is visible, not swallowed.
    if det_rc not in (0, 2):
        any_error = True
        if det_err:
            print(det_err, file=sys.stderr, end="")
    else:
        codes.append(det_rc)
    print(det_out)

    # Banner is a NOTE to the agent, not report data — keep it off stdout so it
    # does not pollute the `## `-delimited deterministic report.
    print(missing_legs_banner(set()), file=sys.stderr)
    return rollup_exit(codes, any_error)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
