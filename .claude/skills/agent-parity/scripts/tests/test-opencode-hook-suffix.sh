#!/usr/bin/env bash
# Verify opencode extract_hooks normalizes .js/.ts suffixes with BSD-compatible
# sed -E (not the GNU-only sed 's/\.\(js\|ts\)$//' alternation, which is a
# silent no-op on Darwin and used to leave "rtk.ts" unstripped).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRACTORS_DIR="$(cd "$SCRIPT_DIR/../extractors" && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOOKS_DIR="$TMP_ROOT/plugins"
mkdir -p "$HOOKS_DIR"
printf '// fake\n' > "$HOOKS_DIR/rtk.ts"
printf '// fake\n' > "$HOOKS_DIR/block-main-edit.js"

# shellcheck source=/dev/null
source "$EXTRACTORS_DIR/opencode.sh"

EXTRACTOR_HOOKS_DIR="$HOOKS_DIR"
export EXTRACTOR_HOOKS_DIR
RESULT="$(extract_hooks "")"

echo "$RESULT" | grep -qx 'rtk' || {
  echo "FAIL: expected 'rtk' (suffix stripped from rtk.ts), got:" >&2
  echo "$RESULT" >&2
  exit 1
}
echo "$RESULT" | grep -qx 'block-main-edit' || {
  echo "FAIL: expected 'block-main-edit' (suffix stripped from block-main-edit.js), got:" >&2
  echo "$RESULT" >&2
  exit 1
}
if echo "$RESULT" | grep -q '\.ts$\|\.js$'; then
  echo "FAIL: suffix was not stripped, sed alternation regressed" >&2
  echo "$RESULT" >&2
  exit 1
fi

echo "PASS: opencode extract_hooks strips .js/.ts suffixes on Darwin"
