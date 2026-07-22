#!/usr/bin/env bash
# freeze-corpus-missing-test-prompts-na.sh
# Regression for the 3-strikes bug: a skill with trigger-eval.json but NO
# test-prompts.json must FREEZE PROCEED (exit 0) under auto-pipeline-improve,
# not exit 2. A2 then decides surrogate-or-N/A per its own contract.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main; git config user.email t@t; git config user.name t
mkdir -p sk/evals
echo '{"name":"sk","description":"x"}' > sk/SKILL.md
echo '[{"q":"a","should_trigger":true}]' > sk/evals/trigger-eval.json
# NOTE: deliberately NO sk/test-prompts.json and NO adversarial-cases.json
git add . && git commit -q -m init
trust="$(git rev-parse HEAD)"
RUN="$TMP/run"; mkdir -p "$RUN"

# Case 1: missing test-prompts.json in auto-pipeline-improve → exit 0, not 2
set +e
out="$("$HERE/freeze-corpus.sh" sk "$trust" "$RUN" --pipeline-mode auto-pipeline-improve 2>"$TMP/err")"
rc=$?
set -e
err="$(cat "$TMP/err")"
[ "$rc" -eq 0 ] || { echo "FAIL: expected exit 0, got $rc"; echo "stderr: $err"; exit 1; }
echo "$out" | grep -q '^frozen_root=' || { echo "FAIL: no frozen_root= line"; exit 1; }
echo "$err" | grep -qi 'no test-prompts.json' || { echo "FAIL: missing [INFO] test-prompts line; stderr: $err"; exit 1; }
# trigger-eval still frozen (A1 corpus present)
test -f "$RUN/frozen-corpus/sk/evals/trigger-eval.json" || { echo "FAIL: trigger-eval not frozen"; exit 1; }
# test-prompts NOT frozen (absent, correctly skipped — no empty file left)
test ! -f "$RUN/frozen-corpus/sk/test-prompts.json" || { echo "FAIL: empty test-prompts left behind"; exit 1; }
echo "PASS: missing test-prompts.json (improve) → exit 0 + [INFO], A1 frozen"

# Case 2: missing trigger-eval.json STILL hard-stops (A1 has no N/A path)
RUN2="$TMP/run2"; mkdir -p "$RUN2"
rm -rf "$TMP/sk2"; mkdir -p sk2/evals
echo '{"name":"sk2","description":"x"}' > sk2/SKILL.md
echo '[{"id":1,"prompt":"x","expected":"y"}]' > sk2/test-prompts.json
# NO trigger-eval.json
git add . && git commit -q -m sk2
trust2="$(git rev-parse HEAD)"
set +e
"$HERE/freeze-corpus.sh" sk2 "$trust2" "$RUN2" --pipeline-mode auto-pipeline-improve >/dev/null 2>&1
rc2=$?
set -e
[ "$rc2" -eq 2 ] || { echo "FAIL: missing trigger-eval should exit 2, got $rc2"; exit 1; }
echo "PASS: missing trigger-eval.json (improve) → still exit 2 (A1 hard-required)"

echo "ALL PASS: freeze-corpus-missing-test-prompts-na"
