#!/usr/bin/env bash
# Verify the OpenCode plugin stays aligned with manifest-declared external hooks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

expected="$(mktemp)"
actual="$(mktemp)"
trap 'rm -f "$expected" "$actual"' EXIT

jq -r '
  .hooks[]
  | .harnesses.opencode.externalHook? // empty
' "$HOOK_ROOT/manifest.json" | sort -u > "$expected"

rg -o '[a-z-]+\.sh' "$HOOK_ROOT/opencode/skill-dev-hooks.ts" \
  | sed 's/\.sh$//' \
  | sort -u > "$actual"

if ! diff "$expected" "$actual" >/dev/null; then
  echo "FAIL: OpenCode plugin hook set does not match hooks/manifest.json" >&2
  diff "$expected" "$actual" >&2
  exit 1
fi

echo "PASS: OpenCode plugin hook set matches hooks/manifest.json"
