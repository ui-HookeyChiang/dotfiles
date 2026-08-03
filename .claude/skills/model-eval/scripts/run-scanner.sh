#!/bin/sh
# usage: run-scanner.sh <model> <run_idx> [effort]
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"; IDX="$2"; EFFORT="${3:-low}"
OUT="${MODEL_EVAL_OUT:-$HOME/model-eval-out}"
RUN="$OUT/scanner-$MODEL-$IDX"
rm -rf "$RUN"; mkdir -p "$RUN"
PROMPT="Classify each ticket item below. Canonical statuses: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix, done. Normalize case/spacing. If no Status line is present, the item is needs-triage. Extract the date from the filename (null if none).

Output ONLY a JSON object: {\"<item number>\": {\"date\": \"YYYY-MM-DD\"|null, \"status\": \"<canonical>\"}} for all 12 items. No other text.

$(cat "$SKILL/fixtures/scanner/corpus.txt")"
START=$(date +%s%3N)
(cd "$RUN" && printf '%s' "$PROMPT" | sh "$SKILL/scripts/cli-run.sh" "$MODEL" "$EFFORT" 4 claude.json 2> stderr.log)
END=$(date +%s%3N)
export MODEL IDX EFFORT LAT=$((END-START)) RUN OUT SKILL
python3 - << 'PY'
import json, os, re
run, skill, out = os.environ["RUN"], os.environ["SKILL"], os.environ["OUT"]
try: d = json.load(open(run + "/claude.json"))
except Exception: d = {}
u = d.get("usage", {})
res = d.get("result") or ""
ans = {}
i = res.find("{")
if i >= 0:
    try: ans = json.JSONDecoder().raw_decode(res[i:])[0]
    except Exception: ans = {}
truth = json.load(open(skill + "/fixtures/scanner/truth.json"))
correct = 0
for k, t in truth.items():
    a = ans.get(k) or {}
    correct += int((a.get("date") or None) == t["date"])
    correct += int((a.get("status") or "").strip().lower() == t["status"])
rec = {"q": "scanner", "model": os.environ["MODEL"], "run": os.environ["IDX"],
       "effort": os.environ["EFFORT"], "accuracy": round(correct / (2 * len(truth)), 3),
       "correct": correct, "total": 2 * len(truth), "parse_ok": bool(ans),
       "cost_usd": d.get("total_cost_usd"), "out_tok": u.get("output_tokens"),
       "latency_ms": int(os.environ["LAT"])}
with open(out + "/ledger.jsonl", "a") as f:
    f.write(json.dumps(rec) + "\n")
print("scanner", os.environ["MODEL"], "#" + os.environ["IDX"], "acc", rec["accuracy"])
PY
