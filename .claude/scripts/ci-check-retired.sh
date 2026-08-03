#!/usr/bin/env bash
# ci-check-retired.sh — verify that any name removed from EXTRAS_NAMES or the
# mattpocock -s skill list appears in retired-skills.txt.
# Exit 1 if a name was dropped without a manifest entry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/retired-skills.txt"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: $MANIFEST not found" >&2
  exit 1
fi

# Collect retired names from manifest (strip comments and blank lines)
retired_names=()
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  name="${line%%:*}"
  case "$name" in */*|..|.) echo "ERROR: retired-skills.txt: unsafe name '${name}'" >&2; exit 1 ;; esac
  retired_names+=("$name")
done < "$MANIFEST"

# Extract names removed from install.sh relative to HEAD~1.
# We look at two sections:
#   1. EXTRAS_NAMES array entries (quoted strings inside the array)
#   2. mattpocock -s skill names from EXTRAS_INSTALL_CMDS

# Get the diff of install.sh against parent commit.
# If no parent (initial commit), skip — nothing to compare.
if ! git -C "$REPO_ROOT" rev-parse HEAD~1 >/dev/null 2>&1; then
  echo "ci-check-retired: no parent commit, skipping removal check"
  exit 0
fi

DIFF="$(git -C "$REPO_ROOT" diff HEAD~1 HEAD -- install.sh 2>/dev/null || true)"

if [ -z "$DIFF" ]; then
  echo "ci-check-retired: install.sh unchanged, nothing to check"
  exit 0
fi

# Lines removed (prefixed with -) from install.sh
removed_lines="$(echo "$DIFF" | grep '^-' | grep -v '^---' || true)"

# Extract EXTRAS_NAMES entries: quoted strings in the EXTRAS_NAMES array block.
# Pattern: lines like  "name"  inside the EXTRAS_NAMES=( ... ) block.
# We use a simple grep on removed lines.
extras_removed=()
while IFS= read -r rline; do
  # Match lines that look like:  "some-name"  (sole content inside quotes)
  if echo "$rline" | grep -qE '^-[[:space:]]+"[A-Za-z0-9_-]+"[[:space:]]*$'; then
    name="${rline#-}"
    name="${name#"${name%%[! ]*}"}"  # ltrim
    name="${name#\"}"
    name="${name%\"}"
    name="${name%" "}"
    extras_removed+=("$name")
  fi
done <<< "$removed_lines"

# Extract mattpocock -s skill names: lines like   -s skill-name
# from removed lines in install.sh.
mp_removed=()
while IFS= read -r rline; do
  # Find all -s <name> tokens in the removed line
  cleaned="${rline#-}"  # strip leading diff marker
  while [[ "$cleaned" =~ -s[[:space:]]+([A-Za-z0-9_-]+) ]]; do
    mp_removed+=("${BASH_REMATCH[1]}")
    # Advance past this match to find more
    cleaned="${cleaned#*-s }"
    cleaned="${cleaned#"${BASH_REMATCH[1]}"}"
  done
done <<< "$removed_lines"

# Combine all removed names (deduplicate)
declare -A seen_removed=()
all_removed=()
for n in "${extras_removed[@]}" "${mp_removed[@]}"; do
  if [ -z "${seen_removed[$n]+x}" ]; then
    seen_removed[$n]=1
    all_removed+=("$n")
  fi
done

if [ "${#all_removed[@]}" -eq 0 ]; then
  echo "ci-check-retired: no names removed from install.sh, OK"
  exit 0
fi

# Check each removed name is in the manifest
failed=0
for name in "${all_removed[@]}"; do
  found=0
  for r in "${retired_names[@]}"; do
    if [ "$r" = "$name" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "ERROR: '$name' was removed from install.sh but has no entry in retired-skills.txt" >&2
    echo "  Add an entry like:  ${name}:skill,agents-dir  (adjust kinds as needed)" >&2
    failed=1
  fi
done

if [ "$failed" -eq 1 ]; then
  exit 1
fi

echo "ci-check-retired: all removed names covered in retired-skills.txt, OK"
