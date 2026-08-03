#!/usr/bin/env python3
"""Summarize adapter ledgers into per-channel daily quota pressure.

Reads ledger JSON lines (one per `cli-adapter.sh run`), groups by the exact
`(backend, model, effort)` key, and reports today's pressure against the
capacity floor observed on earlier quota days.

Provider caps are hidden, so nothing here claims an absolute quota. A `75`
quota event is a right-censored observation: the runs that succeeded before it
are a LOWER bound on that day's capacity, never the cap itself.

pressure:
  quota today          -> 1.0, available False (that exact key only)
  history exists       -> runs_ok_today / p20(historical capacity_floor)
  no history           -> "N/A" — unknown, never rendered as green/safe

api_equivalent_usd prices tokens at the displaced Anthropic incumbent's API
rates, and usd_saved subtracts what the run actually cost. Both are REPORTING
columns only; dispatch must never throttle on dollars.

latency_ms is summed per channel and shown as ms/run. It is the intended
operational proxy for CLIs that report no token counts, but nothing consumes it
yet — pressure is run-count based today. Wiring it in needs a per-model latency
baseline to compare against, which the ledger cannot yet supply.

Days are bucketed in UTC so a report does not shift with the reporting
machine's local zone.

Usage: quota-estimator.py --ledger <f> [--ledger <f>...] [--format table|json]
                          [--date YYYY-MM-DD]
Exit: 0 report printed, 2 usage error.
"""
import argparse
import glob
import json
import sys
from collections import defaultdict
from datetime import date, datetime, timezone

# USD per 1M tokens, Anthropic API list price for Sonnet 5 (anthropic.com/pricing,
# checked 2026-07-27). Reporting only — a subscription run's real cost is quota,
# not dollars.
#
# One flat rate stands in for every channel, which OVERSTATES savings on the
# scan and execute tiers: model-dispatch binds those to Haiku 4.5, roughly a
# third of this price. Treat the number as an upper bound on displaced spend,
# not an invoice. Per-model rates need a price table keyed by the incumbent
# each tier actually displaces — worth doing once the ledger carries the tier
# the run displaced rather than the tier it ran as.
API_PRICES = {
    "input": 3.00,
    "output": 15.00,
    "cache_read": 0.30,
    "cache_create": 3.75,
}


def utc_date(value):
    """argparse type for --date: YYYY-MM-DD, rejected early rather than
    silently bucketing every record under a nonsense day."""
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"expected YYYY-MM-DD, got {value!r}")


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ledger", action="append", required=True,
                   help="ledger .jsonl path or glob; repeatable")
    p.add_argument("--format", choices=("table", "json"), default="table")
    p.add_argument("--date", type=utc_date,
                   default=datetime.now(timezone.utc).date().isoformat(),
                   help="UTC day to report as 'today' (default: today UTC)")
    return p.parse_args(argv)


def load_records(patterns):
    """Yield ledger records. Malformed lines are skipped, not fatal — a ledger
    is append-only history and one bad line must not blind the estimator."""
    for pattern in patterns:
        paths = sorted(glob.glob(pattern)) or [pattern]
        for path in paths:
            try:
                with open(path) as f:
                    lines = f.readlines()
            except OSError as e:
                print(f"cannot read ledger {path}: {e}", file=sys.stderr)
                raise SystemExit(2)
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if isinstance(rec, dict) and rec.get("backend"):
                    yield rec


def record_day(rec):
    """Ledger day as a UTC YYYY-MM-DD, or None when the record carries no
    timestamp. Offset-aware timestamps convert to UTC; naive ones are read as
    UTC already, so day boundaries agree with `--date` regardless of the
    reporting machine's local zone."""
    ts = rec.get("ts")
    if not isinstance(ts, str):
        return None
    try:
        parsed = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return ts[:10] if len(ts) >= 10 else None
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc)
    return parsed.date().isoformat()


def p20(values):
    """20th percentile, linear interpolation. Conservative on purpose: the low
    end of observed floors is the capacity we can actually count on."""
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    pos = 0.20 * (len(ordered) - 1)
    lo = int(pos)
    hi = min(lo + 1, len(ordered) - 1)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (pos - lo)


def summarize_day(records):
    """Daily totals for one channel-day. capacity_floor is runs_ok BEFORE the
    first quota event, and only meaningful on days that hit quota.

    Records are sorted by `ts` first: the floor depends on run ORDER, so
    interleaved ledger lines would otherwise manufacture a spurious low floor.
    Records without `ts` keep their file order and sort ahead of timestamped
    ones, which is the conservative reading — they count as earlier runs."""
    day = {
        "runs_ok": 0, "runs_quota": 0, "in_tok": 0, "out_tok": 0,
        "cache_read": 0, "cache_create": 0, "latency_ms": 0,
        "cost_usd": 0.0, "last_quota_at": None, "capacity_floor": None,
    }
    ok_before_quota = 0
    seen_quota = False
    for rec in sorted(records, key=lambda r: r.get("ts") or ""):
        if rec.get("quota_exhausted"):
            day["runs_quota"] += 1
            day["last_quota_at"] = rec.get("ts") or day["last_quota_at"]
            if not seen_quota:
                day["capacity_floor"] = ok_before_quota
                seen_quota = True
            continue
        day["runs_ok"] += 1
        if not seen_quota:
            ok_before_quota += 1
        for field in ("in_tok", "out_tok", "cache_read", "cache_create",
                      "latency_ms", "cost_usd"):
            value = rec.get(field)
            if isinstance(value, (int, float)):
                day[field] += value
    return day


def api_equivalent_usd(day):
    return round(
        day["in_tok"] / 1e6 * API_PRICES["input"]
        + day["out_tok"] / 1e6 * API_PRICES["output"]
        + day["cache_read"] / 1e6 * API_PRICES["cache_read"]
        + day["cache_create"] / 1e6 * API_PRICES["cache_create"],
        6,
    )


def estimate(records, today):
    by_key = defaultdict(lambda: defaultdict(list))
    for rec in records:
        key = (rec["backend"], rec.get("model") or "",
               rec.get("effort") if rec.get("effort") is not None else "")
        by_key[key][record_day(rec) or today].append(rec)

    channels = []
    for (backend, model, effort), days in sorted(by_key.items()):
        today_day = summarize_day(days.get(today, []))
        # A zero floor means the day's FIRST record was already a quota event,
        # so it observed no capacity at all. That is unknown, not "capacity 0" —
        # keeping it would divide by nothing and fake a confident answer.
        history = sorted(
            floor
            for floor in (
                summarize_day(recs)["capacity_floor"]
                for day, recs in days.items() if day != today
            )
            if floor
        )

        if today_day["runs_quota"] > 0:
            pressure, available = 1.0, False
        elif history:
            pressure = today_day["runs_ok"] / p20(history)
            available = True
        else:
            pressure, available = "N/A", True

        channels.append({
            "backend": backend, "model": model, "effort": effort,
            "runs_ok": today_day["runs_ok"],
            "runs_quota": today_day["runs_quota"],
            "in_tok": today_day["in_tok"], "out_tok": today_day["out_tok"],
            "cache_read": today_day["cache_read"],
            "cache_create": today_day["cache_create"],
            "latency_ms": today_day["latency_ms"],
            "cost_usd": round(today_day["cost_usd"], 6),
            "usd_saved": round(
                api_equivalent_usd(today_day) - today_day["cost_usd"], 6),
            "last_quota_at": today_day["last_quota_at"],
            "capacity_floor": today_day["capacity_floor"],
            "history_floors": history,
            "pressure": pressure,
            "available": available,
            "api_equivalent_usd": api_equivalent_usd(today_day),
        })
    return {"date": today, "channels": channels}


def render_table(report):
    header = ("backend", "model", "effort", "ok", "quota", "floor",
              "pressure", "avail", "ms/run", "api_usd", "saved")
    rows: list[tuple[str, ...]] = [header]
    for c in report["channels"]:
        pressure = c["pressure"]
        rows.append((
            c["backend"], c["model"], c["effort"] or "-",
            str(c["runs_ok"]), str(c["runs_quota"]),
            "-" if c["capacity_floor"] is None else str(c["capacity_floor"]),
            "N/A" if pressure == "N/A" else f"{pressure:.2f}",
            "yes" if c["available"] else "NO",
            "-" if not c["runs_ok"] else str(
                round(c["latency_ms"] / c["runs_ok"])),
            f"{c['api_equivalent_usd']:.4f}",
            f"{c['usd_saved']:.4f}",
        ))
    widths = [max(len(r[i]) for r in rows) for i in range(len(header))]
    lines = [f"quota pressure for {report['date']} (UTC)", ""]
    for i, row in enumerate(rows):
        lines.append("  ".join(cell.ljust(widths[j])
                               for j, cell in enumerate(row)).rstrip())
        if i == 0:
            lines.append("  ".join("-" * w for w in widths))
    lines += ["", "pressure N/A = no capacity history; UNKNOWN, not safe.",
              "api_usd/saved = reporting only; never the throttle source."]
    return "\n".join(lines)


def main():
    args = parse_args(sys.argv[1:])
    report = estimate(list(load_records(args.ledger)), args.date)
    if args.format == "json":
        print(json.dumps(report, indent=2))
    else:
        print(render_table(report))


if __name__ == "__main__":
    main()
