#!/usr/bin/env bash
# SC11 — 5/5 PASS in standalone equivalence mode produces APPROVE.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap "rm -rf $TMP" EXIT
for i in 1 2 3 4 5; do
  mkdir -p "$TMP/private-A$i"
  case $i in
    1) v=TRIGGER_PASS ;;
    2) v=BEHAVIOR_PASS ;;
    3) v=EQUIVALENT ;;
    4) v=CONTRACT_HELD ;;
    5) v=ROBUST ;;
  esac
  cat > "$TMP/private-A$i/ballot.json" <<EOF
{"voter":"A$i","verdict":"$v","confidence":"medium","evidence":[],"concerns":[],"notes":""}
EOF
done
out="$(python3 "$HERE/voting-harness.py" aggregate "$TMP")"
echo "$out" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'APPROVE', f'expected APPROVE got {r[\"outcome\"]}'
assert r['pass_count'] == 5
assert r['voting_total'] == 5
assert r['hc_triggered'] == []
print('PASS: aggregate-5pass')
"
