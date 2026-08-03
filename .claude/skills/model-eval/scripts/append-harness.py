#!/usr/bin/env python3
"""Append one harness-smoke record to $OUT/harness.jsonl from env.

Harness smoke answers "can this channel run at all" — a (backend, model) fact,
read back keyed on that pair. It is a separate stream from the capability
ledger so the capability cell key never grows a backend dimension.

Env: OUT (dir), MODEL, RC (adapter exit code), LAT (ms).
     MODEL_EVAL_CLI names the backend, default "claude".
"""
import json, os

out = os.environ["OUT"]
rc = int(os.environ["RC"])
rec = {
    "backend": os.environ.get("MODEL_EVAL_CLI") or "claude",
    "model": os.environ["MODEL"],
    "rc": rc,
    "latency_ms": int(os.environ["LAT"]),
    "ok": rc == 0,
}
with open(out + "/harness.jsonl", "a") as f:
    f.write(json.dumps(rec) + "\n")
