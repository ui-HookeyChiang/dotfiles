#!/bin/sh
# usage: run-search.sh <model> <run_idx> [effort] [repo_dir]
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"; IDX="$2"; EFFORT="${3:-low}"; REPO="${4:-$PWD}"
OUT="${MODEL_EVAL_OUT:-$HOME/model-eval-out}"
RUN="$OUT/search-$MODEL-$IDX"
rm -rf "$RUN"; mkdir -p "$RUN"
QS=$(python3 -c "
import json
qs = json.load(open('$SKILL/fixtures/search/questions.json'))
print('\n'.join(f\"{q['id']}: {q['q']}\" for q in qs))")
PROMPT="Answer the following questions about the repository at your current directory by investigating it (read-only). If a fact cannot be established from the repository, answer exactly \"unknown\" for that question — do not guess.

$QS

Output ONLY a JSON object: {\"q1\": \"<answer>\", ... \"q7\": \"<answer>\"}. Answers should be short and include the key identifier(s) (script/file/value names)."
START=$(python3 -c 'import time;print(int(time.time()*1000))')
(cd "$REPO" && printf '%s' "$PROMPT" | sh "$SKILL/scripts/cli-run.sh" "$MODEL" "$EFFORT" 20 "$RUN/claude.json" 2> "$RUN/stderr.log")
END=$(python3 -c 'import time;print(int(time.time()*1000))')
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
qs = json.load(open(skill + "/fixtures/search/questions.json"))
correct = 0; abstain_ok = None
for q in qs:
    a = str(ans.get(q["id"]) or "").lower()
    if q.get("abstain"):
        abstain_ok = ("unknown" in a) or (a.strip() in ("", "null", "none"))
        correct += int(bool(abstain_ok))
    else:
        correct += int(all(s.lower() in a for s in q["accept_all"]))
rec = {"q": "search", "model": os.environ["MODEL"], "run": os.environ["IDX"],
       "effort": os.environ["EFFORT"], "accuracy": round(correct/len(qs), 3),
       "abstain_ok": abstain_ok, "num_turns": d.get("num_turns"),
       "parse_ok": bool(ans), "cost_usd": d.get("total_cost_usd"),
       "out_tok": u.get("output_tokens"), "latency_ms": int(os.environ["LAT"])}
with open(out + "/ledger.jsonl", "a") as f: f.write(json.dumps(rec) + "\n")
print("search", rec["model"], "#" + rec["run"], "acc", rec["accuracy"],
      "abstain_ok", abstain_ok, "turns", rec["num_turns"])
PY
