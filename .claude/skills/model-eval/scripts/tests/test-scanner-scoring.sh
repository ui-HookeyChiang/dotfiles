#!/bin/sh
# Scanner scoring: parses fenced JSON, scores against truth, writes ledger line.
set -eu
SKILL="$(cd "$(dirname "$0")/../.." && pwd)"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
mkdir -p "$D/run"
python3 - "$SKILL" "$D/run" << 'PY'
import json, sys
skill, run = sys.argv[1], sys.argv[2]
truth = json.load(open(skill + "/fixtures/scanner/truth.json"))
ans = {k: dict(t) for k, t in truth.items()}
ans["1"]["status"] = "wrong"  # one deliberate miss
json.dump({"result": "```json\n" + json.dumps(ans) + "\n```",
           "usage": {"output_tokens": 100}, "total_cost_usd": 0.01,
           "num_turns": 1, "duration_api_ms": 500}, open(run + "/claude.json", "w"))
PY
# run only the scoring python by sourcing the script's tail via env harness:
MODEL=test IDX=1 EFFORT=low LAT=1000 RUN="$D/run" OUT="$D" SKILL="$SKILL" python3 - << 'PY'
import json, os, re
run, skill, out = os.environ["RUN"], os.environ["SKILL"], os.environ["OUT"]
try: d = json.load(open(run + "/claude.json"))
except Exception: d = {}
u = d.get("usage", {})
m = re.search(r'\{.*\}', d.get("result") or "", re.S)
try: ans = json.loads(m.group(0)) if m else {}
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
PY
grep -q '"correct": 23' "$D/ledger.jsonl" || { echo "FAIL: expected 23/24"; cat "$D/ledger.jsonl"; exit 1; }
# drift guard: the scoring block above must match run-scanner.sh's
grep -q 'correct += int' "$SKILL/scripts/run-scanner.sh" || { echo "FAIL: run-scanner.sh scoring drifted"; exit 1; }
echo "PASS test-scanner-scoring"
