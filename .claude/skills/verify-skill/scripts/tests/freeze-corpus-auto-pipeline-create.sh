#!/usr/bin/env bash
# Regression test: freeze-corpus.sh --pipeline-mode auto-pipeline-create
# falls back to working tree when corpus not in trust root.
# Tracks V2 gap fix from iter-3 e2e dogfood.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main; git config user.email t@t; git config user.name t

# Initial commit with NO skill — trust root predates the skill
echo "seed" > seed.txt
git add . && git commit -q -m seed
trust="$(git rev-parse HEAD)"

# Now author the skill in working tree (not committed, mimics auto-pipeline-create)
mkdir -p sk/evals
echo '{"name":"sk","description":"x"}' > sk/SKILL.md
echo '[{"q":"a","should_trigger":true}]' > sk/evals/trigger-eval.json
echo '[{"id":1,"prompt":"x","expected":"y"}]' > sk/test-prompts.json

RUN="$TMP/run"; mkdir -p "$RUN"

# Without --pipeline-mode flag → must exit 2 (preserves existing contract)
set +e
"$HERE/freeze-corpus.sh" sk "$trust" "$RUN" 2>/dev/null
rc=$?
set -e
if [[ $rc -ne 2 ]]; then
  echo "FAIL: default mode should exit 2 when corpus absent from trust root, got rc=$rc"
  exit 1
fi
echo "  ok: default mode exits 2"

# With --pipeline-mode auto-pipeline-create → must succeed via fallback
out="$("$HERE/freeze-corpus.sh" sk "$trust" "$RUN" --pipeline-mode auto-pipeline-create 2>&1)"
echo "$out" | grep -q '^frozen_root=' || { echo "FAIL: no frozen_root in output"; echo "$out"; exit 1; }
echo "$out" | grep -q '\[WARN\] auto-pipeline-create' || { echo "FAIL: missing WARN line"; echo "$out"; exit 1; }
test -f "$RUN/frozen-corpus/sk/evals/trigger-eval.json" || { echo "FAIL: trigger-eval.json missing"; exit 1; }
test -f "$RUN/frozen-corpus/sk/test-prompts.json" || { echo "FAIL: test-prompts.json missing"; exit 1; }

# Sanity: copied content matches working tree
diff -q sk/evals/trigger-eval.json "$RUN/frozen-corpus/sk/evals/trigger-eval.json" >/dev/null

echo "PASS: freeze-corpus-auto-pipeline-create (V2 gap fix)"
