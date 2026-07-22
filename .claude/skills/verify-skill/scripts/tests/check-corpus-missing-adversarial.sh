#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
mkdir -p "$TMP/skill/evals"
printf -- '---\n' > "$TMP/skill/SKILL.md"
echo '[]' > "$TMP/skill/evals/trigger-eval.json"
echo '[]' > "$TMP/skill/test-prompts.json"
out="$("$HERE/check-corpus.sh" "$TMP/skill")"
echo "$out" | grep -q '^trigger_eval=ok$'
echo "$out" | grep -q '^test_prompts=ok$'
echo "$out" | grep -q '^adversarial=missing$'
echo "PASS: check-corpus-missing-adversarial"
