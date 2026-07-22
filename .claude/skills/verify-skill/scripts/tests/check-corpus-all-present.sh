#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
mkdir -p "$TMP/myskill/evals"
printf -- '---\n' > "$TMP/myskill/SKILL.md"
echo '[]' > "$TMP/myskill/evals/trigger-eval.json"
echo '[]' > "$TMP/myskill/test-prompts.json"
echo '{"cases":[]}' > "$TMP/myskill/evals/adversarial-cases.json"
out="$("$HERE/check-corpus.sh" "$TMP/myskill")"
echo "$out" | grep -q '^trigger_eval=ok$'
echo "$out" | grep -q '^test_prompts=ok$'
echo "$out" | grep -q '^adversarial=ok$'
echo "PASS: check-corpus-all-present"
