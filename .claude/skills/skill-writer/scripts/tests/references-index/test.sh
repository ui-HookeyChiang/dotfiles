#!/usr/bin/env bash
# Guardrail: references/INDEX.md must list exactly the live references/*.md files.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/../../.." && pwd)"
REFERENCES_DIR="$SKILL_ROOT/references"
INDEX="$REFERENCES_DIR/INDEX.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

find "$REFERENCES_DIR" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort > "$TMP/actual"
grep -E '^\| `[^`]+\.md` \|' "$INDEX" \
  | sed -E 's/^\| `([^`]+)` \|.*/\1/' \
  | sort > "$TMP/indexed"

sort "$TMP/indexed" | uniq -d > "$TMP/dupes"
comm -23 "$TMP/actual" "$TMP/indexed" > "$TMP/missing"
comm -13 "$TMP/actual" "$TMP/indexed" > "$TMP/dead"

failed=0
if [[ -s "$TMP/dupes" ]]; then
  echo "FAIL: duplicate INDEX.md reference rows:"
  cat "$TMP/dupes"
  failed=1
fi
if [[ -s "$TMP/missing" ]]; then
  echo "FAIL: live references missing from INDEX.md:"
  cat "$TMP/missing"
  failed=1
fi
if [[ -s "$TMP/dead" ]]; then
  echo "FAIL: INDEX.md lists non-existent references:"
  cat "$TMP/dead"
  failed=1
fi

if [[ "$failed" -eq 0 ]]; then
  echo "PASS: references/INDEX.md matches live references/*.md"
else
  exit 1
fi
