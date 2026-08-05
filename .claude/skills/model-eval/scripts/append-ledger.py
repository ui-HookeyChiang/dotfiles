#!/usr/bin/env python3
"""Append one outcome JSON line to $OUT/ledger.jsonl from env + claude.json."""
import json, os
run, out = os.environ["RUN"], os.environ["OUT"]
try:
    d = json.load(open(run + "/claude.json"))
except Exception:
    d = {}
u = d.get("usage", {})
res = d.get("result") or ""
claimed = "PASS" in res.upper() and "FAIL" not in res.upper().replace("FAILURES", "")
rec = {
    "q": os.environ["Q"], "model": os.environ["MODEL"], "run": os.environ["IDX"],
    "effort": os.environ.get("EFFORT"),
    # Metadata only — never part of the capability cell key (see aggregate.py).
    "backend": os.environ.get("MODEL_EVAL_CLI") or "claude",
    "pass": os.environ.get("PASS") == "true",
    "test_last": os.environ.get("TEST_LAST", ""),
    "touched_forbidden": os.environ.get("TF") == "true",
    "false_done": claimed and os.environ.get("PASS") != "true",
    "num_turns": d.get("num_turns"), "cost_usd": d.get("total_cost_usd"),
    "in_tok": u.get("input_tokens"), "out_tok": u.get("output_tokens"),
    "cache_create": u.get("cache_creation_input_tokens"),
    "cache_read": u.get("cache_read_input_tokens"),
    "latency_ms": int(os.environ["LAT"]), "api_ms": d.get("duration_api_ms"),
}
if os.environ.get("TIER"):
    rec["tier"] = os.environ["TIER"]
# Optional executor-v4 fields: hidden guard verdict + whether sources were edited.
for key, env in (("hidden_ok", "HIDDEN_OK"), ("edited", "EDITED")):
    v = os.environ.get(env)
    if v:
        rec[key] = v == "true"
with open(out + "/ledger.jsonl", "a") as f:
    f.write(json.dumps(rec) + "\n")
