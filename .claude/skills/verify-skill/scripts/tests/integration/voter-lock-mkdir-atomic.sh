#!/usr/bin/env bash
# SC17 — mkdir-atomic lock is single-winner under race.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
PD="$TMP/private-A1"; mkdir -p "$PD"

# Spawn 10 racers; exactly one must win.
winners_file="$TMP/winners"; : > "$winners_file"
for i in $(seq 1 10); do
  (
    if "$HERE/voter-lock.sh" acquire "$PD" 2>/dev/null; then
      echo "$i" >> "$winners_file"
    fi
  ) &
done
wait
count=$(wc -l < "$winners_file")
test "$count" -eq 1 || { echo "FAIL: $count winners (expected 1)"; cat "$winners_file"; exit 1; }
echo "PASS: voter-lock-mkdir-atomic (1 winner of 10 racers)"
