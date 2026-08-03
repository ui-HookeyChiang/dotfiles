#!/usr/bin/env bash
# Mark local ticket/spec status files done after all prerequisite merge events succeed.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ticket-done.sh [--ticket <path> ...] [--prd <path>]

Env:
  FLOW_MERGE_TICKETS   Colon-separated ticket paths.
  FLOW_MERGE_PRD       Optional spec/PRD path.
EOF
}

FILES=()
if [[ -n "${FLOW_MERGE_TICKETS:-}" ]]; then
  IFS=':' read -r -a FILES <<<"$FLOW_MERGE_TICKETS"
fi
if [[ -n "${FLOW_MERGE_PRD:-}" ]]; then
  FILES+=("$FLOW_MERGE_PRD")
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)
      FILES+=("${2:-}"); shift 2 ;;
    --prd)
      FILES+=("${2:-}"); shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage; exit 2 ;;
  esac
done

if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "SKIP: no ticket or PRD paths supplied"
  exit 0
fi

updated=0
for file in "${FILES[@]}"; do
  [[ -n "$file" ]] || continue
  if [[ ! -f "$file" ]]; then
    echo "ERROR: status file not found: $file" >&2
    exit 1
  fi
  python3 - "$file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
patterns = [
    r'^(\*\*Status:\*\*\s*)([^\n]+)',
    r'^(Status:\s*)([^\n]+)',
    r'^(status:\s*)([^\n]+)',
]
for pattern in patterns:
    match = re.search(pattern, text, flags=re.M)
    if not match:
        continue
    if match.group(2).strip() == "done":
        raise SystemExit(0)
    next_text = re.sub(pattern, r'\1done', text, count=1, flags=re.M)
    path.write_text(next_text)
    raise SystemExit(0)
raise SystemExit(f"no Status/status line found in {path}")
PY
  updated=$((updated + 1))
done

echo "OK: marked $updated status file(s) done"
