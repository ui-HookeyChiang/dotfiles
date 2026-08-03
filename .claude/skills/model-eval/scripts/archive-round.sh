#!/usr/bin/env bash
# archive-round.sh — copy binding-relevant eval rows to repo evidence.
# Usage: archive-round.sh <round-slug> [--filter <jq-filter>] [--ledger <path>]
#
# Output: model-eval/evidence/ledger-<date>-<round-slug>.jsonl
# Refuses to overwrite existing evidence files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVIDENCE_DIR="$SCRIPT_DIR/../evidence"
LEDGER="${MODEL_EVAL_OUT:-$HOME/model-eval-out}/ledger.jsonl"
FILTER="."
SLUG=""

usage() {
  echo "Usage: archive-round.sh <round-slug> [--filter <jq-filter>] [--ledger <path>]" >&2
  exit 1
}

[ $# -ge 1 ] || usage
SLUG="$1"; shift

while [ $# -gt 0 ]; do case "$1" in
  --filter) FILTER="$2"; shift 2;;
  --ledger) LEDGER="$2"; shift 2;;
  *) usage;;
esac; done

[ -n "$SLUG" ] || usage
[ -f "$LEDGER" ] || { echo "ledger not found: $LEDGER" >&2; exit 1; }

DATE="$(date +%Y-%m-%d)"
OUT_FILE="$EVIDENCE_DIR/ledger-${DATE}-${SLUG}.jsonl"

if [ -f "$OUT_FILE" ]; then
  echo "ERROR: evidence file already exists: $OUT_FILE" >&2
  echo "Refusing to overwrite — use a different slug or remove manually." >&2
  exit 1
fi

mkdir -p "$EVIDENCE_DIR"
jq -c "select($FILTER)" "$LEDGER" > "$OUT_FILE"

ROWS=$(wc -l < "$OUT_FILE" | tr -d ' ')
echo "Archived $ROWS rows to $OUT_FILE"
