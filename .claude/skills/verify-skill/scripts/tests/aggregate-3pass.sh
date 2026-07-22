#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
for i in 1 2 3; do mkdir -p "$TMP/private-A$i"; done
echo '{"voter":"A1","verdict":"TRIGGER_PASS","confidence":"medium","concerns":[],"notes":""}' > "$TMP/private-A1/ballot.json"
echo '{"voter":"A2","verdict":"BEHAVIOR_PASS","confidence":"medium","concerns":[],"notes":""}' > "$TMP/private-A2/ballot.json"
echo '{"voter":"A3","verdict":"EQUIVALENT","confidence":"medium","concerns":[],"notes":""}' > "$TMP/private-A3/ballot.json"
mkdir -p "$TMP/private-A4" "$TMP/private-A5"
echo '{"voter":"A4","verdict":"CONTRACT_BROKEN","confidence":"medium","concerns":["x"],"notes":""}' > "$TMP/private-A4/ballot.json"
echo '{"voter":"A5","verdict":"FRAGILE","confidence":"medium","concerns":["y"],"notes":""}' > "$TMP/private-A5/ballot.json"
python3 "$HERE/voting-harness.py" aggregate "$TMP" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'NEEDS_HUMAN', f'got {r[\"outcome\"]}'
assert r['pass_count'] == 3 and r['fail_count'] == 2
print('PASS: aggregate-3pass')
"
