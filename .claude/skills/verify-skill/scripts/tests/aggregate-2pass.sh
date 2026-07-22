#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
for i in 1 2 3 4 5; do mkdir -p "$TMP/private-A$i"; done
echo '{"voter":"A1","verdict":"TRIGGER_PASS","confidence":"medium","concerns":[],"notes":""}' > "$TMP/private-A1/ballot.json"
echo '{"voter":"A2","verdict":"BEHAVIOR_PASS","confidence":"medium","concerns":[],"notes":""}' > "$TMP/private-A2/ballot.json"
echo '{"voter":"A3","verdict":"DIVERGED","confidence":"medium","concerns":["x"],"notes":""}' > "$TMP/private-A3/ballot.json"
echo '{"voter":"A4","verdict":"CONTRACT_BROKEN","confidence":"medium","concerns":["y"],"notes":""}' > "$TMP/private-A4/ballot.json"
echo '{"voter":"A5","verdict":"FRAGILE","confidence":"medium","concerns":["z"],"notes":""}' > "$TMP/private-A5/ballot.json"
# REJECT outcome returns exit 1 per harness contract; capture stdout and
# tolerate the non-zero exit so the assertion below can run.
out="$(python3 "$HERE/voting-harness.py" aggregate "$TMP" || true)"
echo "$out" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'REJECT', f'got {r[\"outcome\"]}'
print('PASS: aggregate-2pass')
"
