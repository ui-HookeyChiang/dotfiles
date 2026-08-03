#!/usr/bin/env python3
"""Aggregate ledger.jsonl into per-capability-cell summary. Usage: aggregate.py <ledger.jsonl>

Capability cell key is (tier, q, model, lang, effort) — deliberately WITHOUT
backend, so evidence for an identical model id transfers across channels.
Missing effort/tier default to "" at read time; pre-2026-07-27 rows aggregate
as effort/tier-unknown cells rather than being migrated.
"""
import json, sys
from collections import defaultdict


def cell(r):
    return (r.get("tier") or "", r["q"], r["model"], r.get("lang", ""), r.get("effort") or "")


recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
latest = {}
for r in recs:  # dedupe reruns: last entry wins
    latest[cell(r) + (str(r["run"]),)] = r


def avg(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else 0


agg = defaultdict(list)
for r in latest.values():
    agg[cell(r)].append(r)
for (tier, q, m, lang, effort), rs in sorted(agg.items()):
    cost = sum(r.get("cost_usd") or 0 for r in rs)
    line = f"{q} {m}{' [' + lang + ']' if lang else ''}: n={len(rs)}"
    if effort:
        line += f" effort={effort}"
    if tier:
        line += f" tier={tier}"
    if any("pass" in r for r in rs):
        p = sum(bool(r.get("pass")) for r in rs)
        line += f" pass={p}/{len(rs)} cost/pass=${cost / max(p, 1):.3f}"
        fd = sum(bool(r.get("false_done")) for r in rs)
        if fd:
            line += f" FALSE_DONE={fd}"
    if any("accuracy" in r for r in rs):
        line += f" acc={avg([r.get('accuracy') for r in rs]):.2f}"
    line += (f" out_tok={avg([r.get('out_tok') for r in rs]):.0f}"
             f" lat={avg([r.get('latency_ms') for r in rs]) / 1000:.0f}s cost=${cost:.3f}")
    print(line)
