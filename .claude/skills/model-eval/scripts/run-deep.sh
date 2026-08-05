#!/bin/sh
# usage: run-deep.sh <model> <run_idx> [effort] [fixture:v1|v2]
# Diagnosis only — code + symptom log inline, no tools, no fixing.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"; IDX="$2"; EFFORT="${3:-low}"; TIER="${4:-v1}"
case "$TIER" in v1) FIX="$SKILL/fixtures/deep" ;; *) FIX="$SKILL/fixtures/deep-$TIER" ;; esac
OUT="${MODEL_EVAL_OUT:-$HOME/model-eval-out}"
RUN="$OUT/deep-$TIER-$MODEL-$IDX"
rm -rf "$RUN"; mkdir -p "$RUN"
TRAP_FIELD=$(python3 -c "import json;print(json.load(open('$FIX/truth.json')).get('trap_field','is_wt_id_defective'))")
TRAP_Q=$(python3 -c "import json;print(json.load(open('$FIX/truth.json')).get('trap_question',''))")
SRC=$(/bin/cat "$FIX"/*.c "$FIX"/*.sh 2>/dev/null)
PROMPT="A system reports the failure below. Diagnose the ROOT CAUSE(S). Do not propose fixes; identify the defective function(s) and the exact defect. Trace the causal chain — the frames/tests that surface the failure may or may not be where the defect lives. ($TRAP_Q)

=== symptom ===
$(cat "$FIX/symptom.log")

=== source under suspicion ===
$SRC

Output ONLY JSON: {\"root_causes\": [{\"function\": \"<name>\", \"defect\": \"<one sentence>\"}], \"$TRAP_FIELD\": true|false}."
START=$(python3 -c 'import time;print(int(time.time()*1000))')
(cd "$RUN" && printf '%s' "$PROMPT" | sh "$SKILL/scripts/cli-run.sh" "$MODEL" "$EFFORT" 4 claude.json 2> stderr.log)
END=$(python3 -c 'import time;print(int(time.time()*1000))')
export MODEL IDX EFFORT LAT=$((END-START)) RUN OUT FIX TIER TRAP_FIELD
python3 - << 'PY'
import json, os, re
run, fix, out = os.environ["RUN"], os.environ["FIX"], os.environ["OUT"]
try: d = json.load(open(run + "/claude.json"))
except Exception: d = {}
u = d.get("usage", {})
res = d.get("result") or ""
ans = {}
i = res.find("{")
if i >= 0:
    try: ans = json.JSONDecoder().raw_decode(res[i:])[0]
    except Exception: ans = {}
truth = json.load(open(fix + "/truth.json"))
text = json.dumps(ans).lower()
hits = sum(any(s.lower() in text for s in rc["accept_any"]) for rc in truth["root_causes"])
trap = bool(ans.get(os.environ["TRAP_FIELD"]))
rec = {"q": "deep-" + os.environ["TIER"], "model": os.environ["MODEL"], "run": os.environ["IDX"],
       "effort": os.environ["EFFORT"],
       "causes_hit": hits, "causes_total": len(truth["root_causes"]),
       "fell_for_trap": trap,
       "pass": hits == len(truth["root_causes"]) and not trap,
       "parse_ok": bool(ans), "cost_usd": d.get("total_cost_usd"),
       "out_tok": u.get("output_tokens"), "latency_ms": int(os.environ["LAT"])}
with open(out + "/ledger.jsonl", "a") as f: f.write(json.dumps(rec) + "\n")
print("deep-" + os.environ["TIER"], rec["model"], "#" + rec["run"], "hit",
      f"{hits}/{rec['causes_total']}", "trap", trap, "pass", rec["pass"])
PY
