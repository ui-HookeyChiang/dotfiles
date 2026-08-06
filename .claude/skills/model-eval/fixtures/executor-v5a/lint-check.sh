#!/bin/sh
# lint-check.sh — validate a YAML-like config file before build.
# Checks: file exists, required keys present, no tab indentation, balanced braces.
# Exit 0 = clean, non-zero = lint errors found.
set -e

file="${1:?usage: lint-check.sh <config-file>}"

if [ ! -f "$file" ]; then
  echo "lint-check: file not found: $file" >&2
  exit 1
fi

errors=0

for key in name version host port timeout retry_limit; do
  if ! grep -q "^${key}:" "$file"; then
    echo "lint-check: missing required key '$key'" >&2
    errors=$((errors + 1))
  fi
done

if grep -qP '\t' "$file" 2>/dev/null || grep -q '	' "$file"; then
  echo "lint-check: tab indentation found (use spaces)" >&2
  errors=$((errors + 1))
fi

open=$(grep -o '{' "$file" | wc -l | tr -d ' ')
close=$(grep -o '}' "$file" | wc -l | tr -d ' ')
if [ "$open" != "$close" ]; then
  echo "lint-check: unbalanced braces (open=$open close=$close)" >&2
  errors=$((errors + 1))
fi

if [ $errors -gt 0 ]; then
  echo "lint-check: $errors error(s) found" >&2
  exit 1
fi

echo "lint-check: $file OK"
exit 0
