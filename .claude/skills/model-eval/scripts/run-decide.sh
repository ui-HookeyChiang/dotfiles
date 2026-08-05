#!/bin/sh
# usage: run-decide.sh <model> <run_idx> [effort]
# Trade-off judgment: 6 architectural decisions with objectively better choices.
# Machine-scored: correct choice + reasoning keyword coverage.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"; IDX="$2"; EFFORT="${3:-low}"
OUT="${MODEL_EVAL_OUT:-$HOME/model-eval-out}"
FIX="$SKILL/fixtures/decide"
CASES=$(python3 -c "import json;print(len(json.load(open('$FIX/cases.json'))))")

for ci in $(seq 0 $((CASES - 1))); do
  CASE_ID=$(python3 -c "import json;print(json.load(open('$FIX/cases.json'))[$ci]['id'])")
  RUN="$OUT/decide-$MODEL-$IDX-$CASE_ID"
  rm -rf "$RUN"; mkdir -p "$RUN"

  PROMPT=$(python3 -c "
import json
c = json.load(open('$FIX/cases.json'))[$ci]
print(c['title'])
print()
print(c['context'])
print()
print(c['question'])
")

  START=$(python3 -c 'import time;print(int(time.time()*1000))')
  (cd "$RUN" && printf '%s' "$PROMPT" | sh "$SKILL/scripts/cli-run.sh" "$MODEL" "$EFFORT" 4 claude.json 2> stderr.log)
  END=$(python3 -c 'import time;print(int(time.time()*1000))')

  export MODEL IDX EFFORT CI="$ci" CASE_ID FIX RUN OUT LAT=$((END-START))
  python3 - << 'PY'
import json, os

ci = int(os.environ["CI"])
run, fix, out = os.environ["RUN"], os.environ["FIX"], os.environ["OUT"]
case = json.load(open(fix + "/cases.json"))[ci]

try:
    d = json.load(open(run + "/claude.json"))
except Exception:
    d = {}

u = d.get("usage", {})
res = d.get("result") or ""

ans = {}
i = res.find("{")
if i >= 0:
    try:
        ans = json.JSONDecoder().raw_decode(res[i:])[0]
    except Exception:
        ans = {}

choice = (ans.get("choice") or "").lower().strip()
correct = case["correct_choice"].lower()
chose_correct = choice == correct
chose_trap = choice == case["trap"].lower()

text = json.dumps(ans).lower()
reasoning_hits = sum(
    any(kw.lower() in text for kw in [kw])
    for kw in case["accept_reasoning"]
)
reasoning_total = len(case["accept_reasoning"])

identified_risks = bool(ans.get("risks_of_chosen")) and bool(ans.get("risks_of_rejected"))

rec = {
    "q": "decide", "model": os.environ["MODEL"], "run": os.environ["IDX"],
    "case": os.environ["CASE_ID"], "effort": os.environ["EFFORT"],
    "choice": choice, "correct": chose_correct, "chose_trap": chose_trap,
    "reasoning_hits": reasoning_hits, "reasoning_total": reasoning_total,
    "identified_risks": identified_risks,
    "pass": chose_correct and reasoning_hits >= reasoning_total // 2,
    "parse_ok": bool(ans),
    "cost_usd": d.get("total_cost_usd"),
    "out_tok": u.get("output_tokens"),
    "latency_ms": int(os.environ["LAT"]),
}

with open(out + "/ledger.jsonl", "a") as f:
    f.write(json.dumps(rec) + "\n")

status = "PASS" if rec["pass"] else "FAIL"
trap_note = " TRAP!" if chose_trap else ""
print(f"decide {rec['model']} #{rec['run']} {os.environ['CASE_ID']}: "
      f"{status} choice={choice} correct={chose_correct}{trap_note} "
      f"reasoning={reasoning_hits}/{reasoning_total}")
PY
done
