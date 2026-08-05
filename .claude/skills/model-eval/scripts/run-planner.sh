#!/bin/sh
# usage: run-planner.sh <model> <run_idx> <context_file> [effort] [mode:contexted|no-context] [repo_dir]
# contexted: context inlined, model plans from it alone (measures decomposition quality).
# no-context: context file WITHHELD; model gets repo_dir read access and must
#   discover facts itself (measures search cost + hidden-dependency discovery),
#   or must ask/abstain when discovery is impossible.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"; IDX="$2"; CTX="$3"; EFFORT="${4:-low}"; MODE="${5:-contexted}"; REPO="${6:-$PWD}"
OUT="${MODEL_EVAL_OUT:-$HOME/model-eval-out}"
RUN="$OUT/planner-$MODE-$MODEL-$IDX"
rm -rf "$RUN"; mkdir -p "$RUN"
TASK="Decompose the work described into independently executable stacked tasks.
Output YAML only: a list of tasks, each with fields: objective, allowed_files,
dependencies (task ids), must_preserve, forbidden_changes, acceptance_tests
(each a concrete runnable command), rollback."
if [ "$MODE" = "contexted" ]; then
  PROMPT="You are the planning controller. Using ONLY the context below, $TASK

CONTEXT:
$(cat "$CTX")"
  WORKDIR="$RUN"
else
  PROMPT="You are the planning controller for the repository at your current directory.
Investigate the repository yourself (read-only) to gather the facts you need, then $TASK
Objective: $(head -3 "$CTX")
If a required fact cannot be established from the repository, list it under unresolved_questions instead of inventing it."
  WORKDIR="$REPO"
fi
START=$(python3 -c 'import time;print(int(time.time()*1000))')
(cd "$WORKDIR" && printf '%s' "$PROMPT" | sh "$SKILL/scripts/cli-run.sh" "$MODEL" "$EFFORT" 20 "$RUN/claude.json" 2> "$RUN/stderr.log")
END=$(python3 -c 'import time;print(int(time.time()*1000))')
python3 - "$RUN" << 'PY'
import json, sys
run = sys.argv[1]
try: d = json.load(open(run + "/claude.json"))
except Exception: d = {}
open(run + "/plan.yaml", "w").write(d.get("result") or "")
PY
export Q="planner-$MODE" MODEL IDX EFFORT LAT=$((END-START)) RUN OUT
PASS="" TF="" TEST_LAST="" python3 "$SKILL/scripts/append-ledger.py"
BYTES=$(wc -c < "$RUN/plan.yaml")
echo "planner-$MODE $MODEL #$IDX plan_bytes=$BYTES (score with references/planner-checklist.md; empty plan = false-done candidate)"
