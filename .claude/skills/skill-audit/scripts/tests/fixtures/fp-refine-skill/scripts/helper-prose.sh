#!/usr/bin/env bash
# helper-prose.sh — prose-root weak-edge fixture.
set -euo pipefail

emit_lines() {
  printf '%s\n' a b c
}

while read -r x; do
  echo "line: $x"
done < <(emit_lines)

echo "data" | awk '
function awk_strip(s) { gsub(/x/, "", s); return s }
{ print awk_strip($0) }
'
