#!/usr/bin/env bash
# Verify local ticket/spec files were already marked done by flow-dev. Never mutates.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: verify-ticket-done.sh [--ticket <path> ...] [--prd <path> ...]

Tickets must have Status: done AND live under docs/ticket/done/.
PRDs are checked for Status: done only.

Env:
  FLOW_MERGE_TICKETS   Colon-separated ticket paths.
  FLOW_MERGE_PRD       Optional spec/PRD path.
EOF
}

TICKETS=()
PRDS=()
if [[ -n "${FLOW_MERGE_TICKETS:-}" ]]; then
  IFS=':' read -r -a TICKETS <<<"$FLOW_MERGE_TICKETS"
fi
if [[ -n "${FLOW_MERGE_PRD:-}" ]]; then
  PRDS+=("$FLOW_MERGE_PRD")
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)
      [[ $# -ge 2 ]] || { echo "ERROR: --ticket needs a path" >&2; usage; exit 2; }
      TICKETS+=("$2"); shift 2 ;;
    --prd)
      [[ $# -ge 2 ]] || { echo "ERROR: --prd needs a path" >&2; usage; exit 2; }
      PRDS+=("$2"); shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage; exit 2 ;;
  esac
done

if [[ "$((${#TICKETS[@]} + ${#PRDS[@]}))" -eq 0 ]]; then
  echo "SKIP: no ticket or PRD paths supplied"
  exit 0
fi

# Prints the file's Status value lowercased, or nothing when no Status line
# exists. Only the header region counts: a fenced example further down must not
# be mistaken for the real status.
status_value() {
  python3 - "$1" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
header = re.split(r'^##\s', text, maxsplit=1, flags=re.M)[0]
for pattern in (r'^\*\*Status:\*\*\s*([^\n]+)', r'^[Ss]tatus:\s*([^\n]+)'):
    match = re.search(pattern, header, flags=re.M)
    if match:
        print(match.group(1).strip().lower())
        break
PY
}

# A ticket path may arrive as either the pre-move or post-move location, and
# either repo-relative (the FLOW_MERGE_TICKETS convention) or absolute. Anchored
# on docs/ticket/done — a directory merely named `done` is not the archive.
is_done_path() {
  local dir
  dir="$(dirname "$1")"
  [[ "$dir" == "docs/ticket/done" || "$dir" == */docs/ticket/done ]]
}

done_twin() {
  local path="$1" dir base
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if is_done_path "$path"; then
    printf '%s\n' "$path"
  else
    printf '%s/done/%s\n' "$dir" "$base"
  fi
}

failed=0
verified=0

for ticket in ${TICKETS+"${TICKETS[@]}"}; do
  [[ -n "$ticket" ]] || continue
  moved="$(done_twin "$ticket")"

  if [[ -f "$moved" ]]; then
    found="$moved"
  elif [[ -f "$ticket" ]]; then
    found="$ticket"
  else
    echo "ERROR: ticket not found at $ticket or $moved" >&2
    failed=1
    continue
  fi

  status="$(status_value "$found")"
  if [[ "$status" != "done" ]]; then
    echo "ERROR: $found is not marked done (Status: ${status:-<none>}) — flow-dev must flip it before merge" >&2
    failed=1
    continue
  fi
  if ! is_done_path "$found"; then
    echo "ERROR: $found is marked done but not moved under docs/ticket/done/" >&2
    failed=1
    continue
  fi
  verified=$((verified + 1))
done

for prd in ${PRDS+"${PRDS[@]}"}; do
  [[ -n "$prd" ]] || continue
  if [[ ! -f "$prd" ]]; then
    echo "ERROR: PRD not found: $prd" >&2
    failed=1
    continue
  fi
  status="$(status_value "$prd")"
  if [[ "$status" != "done" ]]; then
    echo "ERROR: $prd is not marked done (Status: ${status:-<none>})" >&2
    failed=1
    continue
  fi
  verified=$((verified + 1))
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "OK: verified $verified status file(s) done"
