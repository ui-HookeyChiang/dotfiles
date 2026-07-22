#!/usr/bin/env bash
# check-corpus.sh — verify required corpus files are present and valid JSON.
# Emits key=value: trigger_eval=ok|missing|malformed (etc.)
# Exits 0 always (caller decides STOP vs degrade); use stdout to decide.
set -euo pipefail
skill_path="${1:?usage: check-corpus.sh <skill-path>}"

check_one() {
  local label="$1" file="$2"
  if [[ ! -f "$file" ]]; then
    echo "${label}=missing"
    return
  fi
  if python3 -c "import json,sys; json.loads(open('$file').read())" 2>/dev/null; then
    echo "${label}=ok"
  else
    echo "${label}=malformed"
  fi
}

check_one trigger_eval     "$skill_path/evals/trigger-eval.json"
check_one test_prompts     "$skill_path/test-prompts.json"
check_one adversarial      "$skill_path/evals/adversarial-cases.json"
