#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
VALIDATOR="$REPO_ROOT/flow-dev/scripts/validate-handoff-contract.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

VALID="$TMPDIR/valid.json"
cat > "$VALID" <<'JSON'
{
  "task_source": "ticket_list",
  "feature_prefix": "feat/example",
  "default_branch": "main",
  "tasks": [
    {
      "description": "Implement example",
      "test_plan": "Run focused tests",
      "issue_path": "docs/ticket/2026-07-27-example.md"
    }
  ],
  "gates": {
    "satisfied": ["converge", "spec", "decompose"],
    "delegated": ["dev", "fan_in", "integration"]
  }
}
JSON
bash "$VALIDATOR" "$VALID" >/dev/null

echo "PASS [valid handoff accepted]"

INVALID="$TMPDIR/invalid.json"
cat > "$INVALID" <<'JSON'
{
  "task_source": "ticket_list",
  "feature_prefix": "feat/example",
  "default_branch": "main",
  "tasks": [
    {
      "description": "Missing issue path",
      "test_plan": "Run focused tests"
    }
  ],
  "gates": {"satisfied": [], "delegated": []}
}
JSON
if bash "$VALIDATOR" "$INVALID" >/dev/null 2>&1; then
  echo "FAIL: invalid handoff accepted" >&2
  exit 1
fi

echo "PASS [malformed handoff rejected]"
