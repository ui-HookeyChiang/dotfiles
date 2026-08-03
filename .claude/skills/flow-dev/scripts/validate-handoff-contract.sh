#!/usr/bin/env bash
# validate-handoff-contract.sh — deterministic shape check for flow -> flow-dev handoff JSON.
set -euo pipefail

HANDOFF="${1:?Usage: validate-handoff-contract.sh <handoff.json>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="${FLOW_DEV_HANDOFF_CONTRACT:-$SCRIPT_DIR/../references/handoff-contract.json}"

fail() {
  echo "[STOP-SAFE] $1" >&2
  exit 1
}

[[ -f "$HANDOFF" ]] || fail "handoff file not found: $HANDOFF"
[[ -f "$CONTRACT" ]] || fail "contract artifact not found: $CONTRACT"
jq empty "$HANDOFF" >/dev/null 2>&1 || fail "handoff is not valid JSON: $HANDOFF"
jq empty "$CONTRACT" >/dev/null 2>&1 || fail "contract is not valid JSON: $CONTRACT"

missing=$(jq -r --slurpfile c "$CONTRACT" '
  ($c[0].input.required_fields // [])[] as $field
  | select(has($field) | not)
  | $field
' "$HANDOFF")
[[ -z "$missing" ]] || fail "handoff missing required field(s): $(echo "$missing" | paste -sd ', ' -)"

task_source=$(jq -r '.task_source' "$HANDOFF")
if ! jq -e --arg source "$task_source" --slurpfile c "$CONTRACT" '$c[0].input.task_source | index($source)' "$HANDOFF" >/dev/null; then
  fail "invalid task_source '$task_source'"
fi

jq -e '.feature_prefix | type == "string" and length > 0' "$HANDOFF" >/dev/null || fail "feature_prefix must be a non-empty string"
jq -e '.default_branch | type == "string" and length > 0' "$HANDOFF" >/dev/null || fail "default_branch must be a non-empty string"
jq -e '.tasks | type == "array" and length > 0' "$HANDOFF" >/dev/null || fail "tasks must be a non-empty array"
jq -e '.gates | type == "object" and (.satisfied | type == "array") and (.delegated | type == "array")' "$HANDOFF" >/dev/null   || fail "gates must contain satisfied[] and delegated[]"

bad_task=$(jq -r --slurpfile c "$CONTRACT" '
  .tasks
  | to_entries[]
  | . as $task
  | ($c[0].input.task_required_fields // [])[] as $field
  | select($task.value | has($field) | not)
  | "task[\($task.key)] missing \($field)"
' "$HANDOFF" | paste -sd '; ' -)
[[ -z "$bad_task" ]] || fail "$bad_task"

bad_issue=$(jq -r '
  .tasks
  | to_entries[]
  | select((.value.issue_path | type != "string") or (.value.issue_path | test("^docs/ticket/.+[.]md$") | not))
  | "task[\(.key)] invalid issue_path"
' "$HANDOFF" | paste -sd '; ' -)
[[ -z "$bad_issue" ]] || fail "$bad_issue"

bad_text=$(jq -r '
  .tasks
  | to_entries[]
  | select((.value.description | type != "string" or length == 0) or (.value.test_plan | type != "string" or length == 0))
  | "task[\(.key)] empty description/test_plan"
' "$HANDOFF" | paste -sd '; ' -)
[[ -z "$bad_text" ]] || fail "$bad_text"

echo "valid handoff: $HANDOFF"
