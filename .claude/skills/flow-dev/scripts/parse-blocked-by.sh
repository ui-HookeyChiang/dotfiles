#!/bin/bash
# parse-blocked-by.sh — extract Blocked by ticket paths from a ticket file.
# Usage: parse-blocked-by.sh <ticket_path>
# Output: JSON array of ticket paths, e.g. ["docs/ticket/2026-07-25-foo.md"]
#         Empty array [] when unblocked ("None" variants).
# Exit: 0=ok, 1=error (file missing, section missing, unparseable line)

set -euo pipefail

TICKET="${1:?Usage: parse-blocked-by.sh <ticket_path>}"

if [[ ! -f "$TICKET" ]]; then
  echo "[STOP-SAFE] Ticket file not found: $TICKET" >&2
  exit 1
fi

# Extract lines between "## Blocked by" and the next "##" heading (or EOF).
IN_SECTION=false
SECTION_LINES=()
while IFS= read -r line; do
  if [[ "$line" =~ ^##[[:space:]]+Blocked[[:space:]]+by ]]; then
    IN_SECTION=true
    continue
  fi
  if $IN_SECTION; then
    # Next heading ends the section.
    if [[ "$line" =~ ^## ]]; then
      break
    fi
    SECTION_LINES+=("$line")
  fi
done < "$TICKET"

if ! $IN_SECTION; then
  echo "[STOP-SAFE] No '## Blocked by' section in $TICKET" >&2
  exit 1
fi

# Collect non-empty, non-whitespace lines.
CONTENT_LINES=()
for line in "${SECTION_LINES[@]}"; do
  trimmed="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$trimmed" ]] && continue
  CONTENT_LINES+=("$trimmed")
done

# Check for "None" variants (case-insensitive).
if [[ ${#CONTENT_LINES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Single line starting with "None" (covers "None.", "None — can start immediately", etc.)
if [[ ${#CONTENT_LINES[@]} -eq 1 ]] && [[ "${CONTENT_LINES[0]}" =~ ^[Nn]one ]]; then
  echo "[]"
  exit 0
fi

# Parse ticket paths from content lines.
# Supported formats:
#   - docs/ticket/slug.md (reason)
#   `docs/ticket/slug.md`
#   docs/ticket/slug.md
PATHS=()
for line in "${CONTENT_LINES[@]}"; do
  # Strip leading list marker (- or *)
  cleaned="${line#-}"
  cleaned="${cleaned#\*}"
  cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"

  # Extract path: try backtick-wrapped first, then bare path.
  if [[ "$cleaned" =~ \`(docs/ticket/[^\ \`]+\.md)\` ]]; then
    PATHS+=("${BASH_REMATCH[1]}")
  elif [[ "$cleaned" =~ (docs/ticket/[^\ \(\)]+\.md) ]]; then
    PATHS+=("${BASH_REMATCH[1]}")
  else
    echo "[STOP-SAFE] Unparseable Blocked by line in $TICKET: $line" >&2
    exit 1
  fi
done

# Output as JSON array.
JSON="["
for i in "${!PATHS[@]}"; do
  [[ $i -gt 0 ]] && JSON+=","
  JSON+="\"${PATHS[$i]}\""
done
JSON+="]"
echo "$JSON"
