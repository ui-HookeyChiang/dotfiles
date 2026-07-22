#!/usr/bin/env python3
"""verify-skill voting harness: aggregation + verdict rendering.

Pure functions only. NEVER spawns agents. The main agent (Claude harness)
spawns voters and writes their ballots into private-A<n>/ballot.json;
this script ONLY reads ballots and computes verdict.
"""
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RULES_PATH = HERE.parent / "references" / "aggregation-rules.json"


def load_rules(path=None):
    path = Path(path) if path else RULES_PATH
    return json.loads(path.read_text())


def aggregate(ballots, pipeline_mode="standalone", rules=None):
    """Aggregate 5 ballots into a final verdict.

    Args:
        ballots: list of dicts with keys voter / verdict / confidence /
                 evidence / concerns / notes. NOT_APPLICABLE and
                 TIMEOUT_FAIL handled per spec.
        pipeline_mode: 'standalone' | 'auto-pipeline-create' |
                       'auto-pipeline-improve'.
        rules: optional override (test injection); defaults to
               references/aggregation-rules.json.

    Returns:
        dict with: outcome, pass_count, fail_count, na_count,
        voting_total, breakdown, hc_triggered, pipeline_mode_ceiling_applied.
    """
    rules = rules or load_rules()
    PASS = set(rules["pass_verdicts"])
    FAIL = set(rules["fail_verdicts"]) | {rules["timeout_verdict"]}
    NA = set(rules["na_verdicts"])

    passes = 0
    fails = 0
    na = 0
    breakdown = []
    high_conf_fails = 0
    high_conf_concerns_on_pass = 0

    for b in ballots:
        v = b.get("verdict", "")
        c = (b.get("confidence") or "medium").lower()
        concerns = b.get("concerns") or []
        if v in NA:
            na += 1
            breakdown.append({"voter": b.get("voter"), "verdict": v, "confidence": c, "weight": 0})
            continue
        if v in PASS:
            passes += 1
            breakdown.append({"voter": b.get("voter"), "verdict": v, "confidence": c, "weight": 1})
            if c == "high" and concerns:
                high_conf_concerns_on_pass += 1
        elif v in FAIL:
            fails += 1
            breakdown.append({"voter": b.get("voter"), "verdict": v, "confidence": c, "weight": -1})
            if c == "high":
                high_conf_fails += 1
        else:
            # Unknown verdict counts as FAIL low-conf
            fails += 1
            breakdown.append({"voter": b.get("voter"), "verdict": f"UNKNOWN({v})", "confidence": c, "weight": -1})

    voting_total = passes + fails

    # ── Count-based outcome ────────────────────────────────────────────
    if voting_total < 3:
        outcome = "NEEDS_HUMAN"
        count_note = "corpus too thin to verify (voting_total < 3)"
    else:
        key = f"voting_total_{voting_total}"
        if key not in rules["thresholds"]:
            # Should not happen — voting_total bounded 3..5 here
            outcome = "NEEDS_HUMAN"
            count_note = f"unexpected voting_total={voting_total}"
        else:
            table = rules["thresholds"][key]
            outcome = table.get(str(passes), table["default"])
            count_note = f"voting_total={voting_total} passes={passes}"

    # ── HC-1: 5/5 PASS + any high-conf concern → ceiling APPROVE_WITH_NOTES ─
    hc_triggered = []
    if voting_total == 5 and passes == 5 and high_conf_concerns_on_pass >= 1:
        if outcome == "APPROVE":
            outcome = "APPROVE_WITH_NOTES"
            hc_triggered.append("HC-1")

    # ── HC-2: ≥2 high-conf FAIL → ceiling NEEDS_HUMAN ──────────────────
    ceiling_order = ["APPROVE", "APPROVE_WITH_NOTES", "NEEDS_HUMAN", "REJECT"]
    if high_conf_fails >= 2:
        # Outcome can only get worse (move right in list), never better
        idx_now = ceiling_order.index(outcome) if outcome in ceiling_order else len(ceiling_order)
        idx_ceiling = ceiling_order.index("NEEDS_HUMAN")
        if idx_now < idx_ceiling:
            outcome = "NEEDS_HUMAN"
            hc_triggered.append("HC-2")

    # ── Pipeline-mode ceiling (auto-pipeline-improve etc.) ─────────────
    pipeline_ceiling_applied = False
    pm_ceiling = rules["pipeline_mode_ceilings"].get(pipeline_mode)
    if pm_ceiling and outcome == "APPROVE":
        # Auto-pipeline-create: cap at APPROVE_WITH_NOTES (still passes)
        # Auto-pipeline-improve: cap at NEEDS_HUMAN (blocks)
        outcome = pm_ceiling
        pipeline_ceiling_applied = True

    return {
        "outcome": outcome,
        "pass_count": passes,
        "fail_count": fails,
        "na_count": na,
        "voting_total": voting_total,
        "breakdown": breakdown,
        "hc_triggered": hc_triggered,
        "pipeline_mode": pipeline_mode,
        "pipeline_mode_ceiling_applied": pipeline_ceiling_applied,
        "count_note": count_note,
    }


def main(argv):
    if len(argv) < 2:
        print("usage: voting-harness.py aggregate <run-dir> "
              "[--pipeline-mode <mode>] [--output-file <path>]",
              file=sys.stderr)
        return 2
    if argv[1] != "aggregate":
        print(f"unknown command: {argv[1]}", file=sys.stderr)
        return 2
    run_dir = Path(argv[2])
    pipeline_mode = "standalone"
    if "--pipeline-mode" in argv:
        i = argv.index("--pipeline-mode")
        pipeline_mode = argv[i + 1]
    # --output-file <path>: explicit override (default: $RUN_DIR/verdict.json)
    output_file = run_dir / "verdict.json"
    if "--output-file" in argv:
        i = argv.index("--output-file")
        output_file = Path(argv[i + 1])
    ballots = []
    for sub in sorted(run_dir.glob("private-A*/ballot.json")):
        try:
            ballots.append(json.loads(sub.read_text()))
        except Exception as e:
            print(f"WARN: malformed ballot {sub}: {e}", file=sys.stderr)
            ballots.append({"voter": sub.parent.name, "verdict": "TIMEOUT_FAIL",
                            "confidence": "low", "notes": f"malformed_json: {e}"})
    if len(ballots) < 5:
        # Fill missing with TIMEOUT_FAIL (main agent should have written
        # synthetic timeout ballots; this is defensive).
        known = {b.get("voter", "") for b in ballots}
        for n in range(1, 6):
            tag = f"A{n}"
            if not any(tag in v for v in known):
                ballots.append({"voter": f"{tag}-missing", "verdict": "TIMEOUT_FAIL",
                                "confidence": "low", "notes": "ballot file missing at aggregate time"})
    result = aggregate(ballots, pipeline_mode=pipeline_mode)
    payload = json.dumps(result, indent=2)
    print(payload)
    try:
        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_text(payload + "\n")
    except Exception as e:
        print(f"WARN: could not write {output_file}: {e}", file=sys.stderr)
    # Exit codes per spec Error handling
    return {"APPROVE": 0, "APPROVE_WITH_NOTES": 0,
            "NEEDS_HUMAN": 0, "REJECT": 1}.get(result["outcome"], 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
