#!/bin/sh
# usage: run-executor.sh <model> <run_idx> [tier:v1|v2|v3] [effort]
# Env: MODEL_EVAL_OUT (default ./model-eval-out). Appends one JSON line to ledger.jsonl.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"; IDX="$2"; TIER="${3:-v1}"; EFFORT="${4:-low}"
OUT="${MODEL_EVAL_OUT:-$HOME/model-eval-out}"
FIX="$SKILL/fixtures/executor-$TIER"
EXPECTED=$(sh "$FIX/run-tests.sh" 2>/dev/null | tail -1)  # buggy baseline marker
TOTAL=$(sh "$FIX/run-tests.sh" 2>/dev/null | tail -1 | sed 's/pass=\([0-9]*\) fail=\([0-9]*\)/\1+\2/' | bc)
FAILS=$(printf '%s' "$EXPECTED" | sed 's/.*fail=//')
RUN="$OUT/executor-$TIER-$MODEL-$IDX"
rm -rf "$RUN"; mkdir -p "$RUN"
cp "$FIX/parse_worktree_path.sh" "$FIX/run-tests.sh" "$RUN/"
TEST_SHA=$(sha256sum "$RUN/run-tests.sh" | cut -d' ' -f1)
PROMPT="Task contract:
- Objective: tests in ./run-tests.sh report $FAILS failures. Fix the bugs so ALL $TOTAL tests pass.
- allowed_files: ONLY parse_worktree_path.sh in the current directory.
- must_preserve: all function names and signatures; the currently-passing tests.
- forbidden_changes: run-tests.sh (test file), any new files.
- acceptance_test: sh ./run-tests.sh prints pass=$TOTAL fail=0.
- Max 2 fix iterations. Work only in the current directory. When done, state PASS or FAIL based on the final test run."
START=$(date +%s%3N)
(cd "$RUN" && MODEL_EVAL_CLAUDE_SKIP_PERMISSIONS=1 printf '%s' "$PROMPT" | sh "$SKILL/scripts/cli-run.sh" "$MODEL" "$EFFORT" 25 claude.json 2> stderr.log)
END=$(date +%s%3N)
TEST_LAST=$( (cd "$RUN" && sh ./run-tests.sh 2>&1 | tail -1) )
(cd "$RUN" && sh ./run-tests.sh >/dev/null 2>&1); TEST_RC=$?
NOW_SHA=$(sha256sum "$RUN/run-tests.sh" | cut -d' ' -f1)
TF=false; [ "$TEST_SHA" != "$NOW_SHA" ] && TF=true
PASS=false; [ $TEST_RC -eq 0 ] && [ "$TF" = false ] && PASS=true
export Q="executor-$TIER" MODEL IDX PASS TF TEST_LAST EFFORT LAT=$((END-START)) RUN OUT
python3 "$SKILL/scripts/append-ledger.py"
echo "executor-$TIER $MODEL #$IDX pass=$PASS ($TEST_LAST)"
