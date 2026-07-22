#!/usr/bin/env bash
# SC11 (HC-1) — 5/5 PASS with any high-conf concern demotes to APPROVE_WITH_NOTES.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
for i in 1 2 3 4 5; do mkdir -p "$TMP/private-A$i"; done
echo '{"voter":"A1","verdict":"TRIGGER_PASS","confidence":"medium","concerns":[]}' > "$TMP/private-A1/ballot.json"
echo '{"voter":"A2","verdict":"BEHAVIOR_PASS","confidence":"medium","concerns":[]}' > "$TMP/private-A2/ballot.json"
echo '{"voter":"A3","verdict":"EQUIVALENT","confidence":"medium","concerns":[]}' > "$TMP/private-A3/ballot.json"
echo '{"voter":"A4","verdict":"CONTRACT_HELD","confidence":"high","concerns":["latent: SKILL.md refers to script not in scripts/"]}' > "$TMP/private-A4/ballot.json"
echo '{"voter":"A5","verdict":"ROBUST","confidence":"medium","concerns":[]}' > "$TMP/private-A5/ballot.json"
python3 "$HERE/voting-harness.py" aggregate "$TMP" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'APPROVE_WITH_NOTES', f'got {r[\"outcome\"]}'
assert 'HC-1' in r['hc_triggered']
assert r['pass_count'] == 5
print('PASS: high-conf-concern-no-fail')
"
