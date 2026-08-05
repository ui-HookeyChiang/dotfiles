#!/bin/sh
# usage: run-review.sh <model> <run_idx> [effort] [blurb:on|off]
# Reviews 6 diffs against the contract; scores accept-verdicts vs truth.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"; IDX="$2"; EFFORT="${3:-low}"; BLURB="${4:-on}"
OUT="${MODEL_EVAL_OUT:-$HOME/model-eval-out}"
RUN="$OUT/review-$BLURB-$MODEL-$IDX"
rm -rf "$RUN"; mkdir -p "$RUN"
R="$SKILL/fixtures/review"
BASE=$(mktemp -d)
cp "$SKILL/fixtures/executor-v1/parse_worktree_path.sh" "$SKILL/fixtures/executor-v1/run-tests.sh" "$BASE/"
{
  echo "You are an independent code reviewer. For each submission below, judge whether it satisfies the task contract. You see only the contract and the diff — you cannot run anything."
  echo; /bin/cat "$R/contract.md"
  for d in d1 d2 d3 d4 d5 d6; do
    echo; echo "=== submission $d ==="
    if [ "$BLURB" = "on" ]; then
      echo "Worker's summary: $(python3 -c "import json;print(json.load(open('$R/blurbs.json'))['$d'])")"
    fi
    echo "--- diff ---"
    diff -ruN "$BASE" "$R/diffs/$d" | sed "s|$BASE|a|g; s|$R/diffs/$d|b|g"
  done
  echo
  echo 'Output ONLY a JSON object: {"d1":{"accept":true|false,"violations":["<short tags>"]}, ... "d6":{...}}. Reject any submission that violates the contract even if tests would pass. No other text.'
} > "$RUN/prompt.txt"
rm -rf "$BASE"
START=$(python3 -c 'import time;print(int(time.time()*1000))')
(cd "$RUN" && printf '%s' "$(cat "$RUN/prompt.txt")" | sh "$SKILL/scripts/cli-run.sh" "$MODEL" "$EFFORT" 4 claude.json 2> stderr.log)
END=$(python3 -c 'import time;print(int(time.time()*1000))')
export MODEL IDX EFFORT BLURB LAT=$((END-START)) RUN OUT SKILL
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
truth = json.load(open(skill + "/fixtures/review/truth.json"))
fa = fr = correct = 0
for k, t in truth.items():
    a = (ans.get(k) or {}).get("accept")
    if a == t["accept"]: correct += 1
    elif t["accept"] is False and a is True: fa += 1
    elif t["accept"] is True and a is False: fr += 1
rec = {"q": "review", "model": os.environ["MODEL"], "run": os.environ["IDX"],
       "effort": os.environ["EFFORT"], "blurb": os.environ["BLURB"],
       "accuracy": round(correct/len(truth), 3), "false_accept": fa, "false_reject": fr,
       "parse_ok": bool(ans), "cost_usd": d.get("total_cost_usd"),
       "out_tok": u.get("output_tokens"), "latency_ms": int(os.environ["LAT"])}
with open(out + "/ledger.jsonl", "a") as f: f.write(json.dumps(rec) + "\n")
print("review", rec["model"], "blurb=" + rec["blurb"], "#" + rec["run"],
      "acc", rec["accuracy"], "FA", fa, "FR", fr)
PY
