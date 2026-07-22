#!/usr/bin/env bash
# SC15 — auto-pipeline mode applies ceiling on 5/5 PASS.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
for i in 1 2 3 4 5; do mkdir -p "$TMP/private-A$i"; done
echo '{"voter":"A1","verdict":"TRIGGER_PASS","confidence":"medium","concerns":[]}' > "$TMP/private-A1/ballot.json"
echo '{"voter":"A2","verdict":"BEHAVIOR_PASS","confidence":"medium","concerns":[]}' > "$TMP/private-A2/ballot.json"
echo '{"voter":"A3","verdict":"NOT_APPLICABLE","confidence":"high","concerns":[]}' > "$TMP/private-A3/ballot.json"
echo '{"voter":"A4","verdict":"CONTRACT_HELD","confidence":"medium","concerns":[]}' > "$TMP/private-A4/ballot.json"
echo '{"voter":"A5","verdict":"ROBUST","confidence":"medium","concerns":[]}' > "$TMP/private-A5/ballot.json"

python3 "$HERE/voting-harness.py" aggregate "$TMP" --pipeline-mode auto-pipeline-improve | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'NEEDS_HUMAN', f'improve: {r[\"outcome\"]}'
assert r['pipeline_mode_ceiling_applied']
print('PASS: auto-pipeline-improve ceiling')
"
python3 "$HERE/voting-harness.py" aggregate "$TMP" --pipeline-mode auto-pipeline-create | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'APPROVE_WITH_NOTES', f'create: {r[\"outcome\"]}'
assert r['pipeline_mode_ceiling_applied']
print('PASS: auto-pipeline-create ceiling')
"
python3 "$HERE/voting-harness.py" aggregate "$TMP" --pipeline-mode standalone | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'APPROVE', f'standalone: {r[\"outcome\"]}'
assert not r['pipeline_mode_ceiling_applied']
print('PASS: standalone (no ceiling)')
"
