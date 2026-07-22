#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main; git config user.email t@t; git config user.name t
mkdir -p sk/evals
echo '{"name":"sk","description":"x"}' > sk/SKILL.md
echo '[{"q":"a","should_trigger":true}]' > sk/evals/trigger-eval.json
echo '[{"id":1,"prompt":"x","expected":"y"}]' > sk/test-prompts.json
echo '{"cases":[{"id":"e1"}]}' > sk/evals/adversarial-cases.json
git add . && git commit -q -m init
trust="$(git rev-parse HEAD)"
RUN="$TMP/run"; mkdir -p "$RUN"
out="$("$HERE/freeze-corpus.sh" sk "$trust" "$RUN")"
echo "$out" | grep -q '^frozen_root='
test -f "$RUN/frozen-corpus/sk/evals/trigger-eval.json"
test -f "$RUN/frozen-corpus/sk/test-prompts.json"
test -f "$RUN/frozen-corpus/sk/evals/adversarial-cases.json"
echo "PASS: freeze-corpus-from-trust-root"
