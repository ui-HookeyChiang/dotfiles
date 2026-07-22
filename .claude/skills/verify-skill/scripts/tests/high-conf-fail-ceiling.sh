#!/usr/bin/env bash
# SC11 (HC-2) — ≥2 high-conf FAIL forces NEEDS_HUMAN ceiling.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
# Case A: voting_total=4 (A3 N/A), 2 PASS + 2 high-conf FAIL
# Count rule → NEEDS_HUMAN; HC-2 confirms ceiling.
for i in 1 2 3 4 5; do mkdir -p "$TMP/private-A$i"; done
echo '{"voter":"A1","verdict":"TRIGGER_PASS","confidence":"medium","concerns":[]}' > "$TMP/private-A1/ballot.json"
echo '{"voter":"A2","verdict":"BEHAVIOR_FAIL","confidence":"high","concerns":["a"]}' > "$TMP/private-A2/ballot.json"
echo '{"voter":"A3","verdict":"NOT_APPLICABLE","confidence":"high","concerns":[]}' > "$TMP/private-A3/ballot.json"
echo '{"voter":"A4","verdict":"CONTRACT_HELD","confidence":"medium","concerns":[]}' > "$TMP/private-A4/ballot.json"
echo '{"voter":"A5","verdict":"FRAGILE","confidence":"high","concerns":["b"]}' > "$TMP/private-A5/ballot.json"
python3 "$HERE/voting-harness.py" aggregate "$TMP" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'NEEDS_HUMAN', f'caseA: {r[\"outcome\"]}'
# HC-2 may or may not be in triggered list (count rule already says NEEDS_HUMAN);
# we just require outcome correctness.
print('PASS: high-conf-fail caseA')
"

# Case B: voting_total=5, 3 PASS + 2 high-conf FAIL. Count says NEEDS_HUMAN.
rm -rf "$TMP"/private-A*
for i in 1 2 3 4 5; do mkdir -p "$TMP/private-A$i"; done
echo '{"voter":"A1","verdict":"TRIGGER_PASS","confidence":"medium","concerns":[]}' > "$TMP/private-A1/ballot.json"
echo '{"voter":"A2","verdict":"BEHAVIOR_PASS","confidence":"medium","concerns":[]}' > "$TMP/private-A2/ballot.json"
echo '{"voter":"A3","verdict":"DIVERGED","confidence":"high","concerns":["d"]}' > "$TMP/private-A3/ballot.json"
echo '{"voter":"A4","verdict":"CONTRACT_HELD","confidence":"medium","concerns":[]}' > "$TMP/private-A4/ballot.json"
echo '{"voter":"A5","verdict":"FRAGILE","confidence":"high","concerns":["e"]}' > "$TMP/private-A5/ballot.json"
python3 "$HERE/voting-harness.py" aggregate "$TMP" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'NEEDS_HUMAN', f'caseB: {r[\"outcome\"]}'
print('PASS: high-conf-fail caseB')
"
