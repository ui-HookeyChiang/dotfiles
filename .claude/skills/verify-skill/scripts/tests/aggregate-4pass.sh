#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap "rm -rf $TMP" EXIT
for i in 1 2 3 4; do
  mkdir -p "$TMP/private-A$i"
  case $i in
    1) v=TRIGGER_PASS ;;
    2) v=BEHAVIOR_PASS ;;
    3) v=EQUIVALENT ;;
    4) v=CONTRACT_HELD ;;
  esac
  cat > "$TMP/private-A$i/ballot.json" <<EOF
{"voter":"A$i","verdict":"$v","confidence":"medium","evidence":[],"concerns":[],"notes":""}
EOF
done
mkdir -p "$TMP/private-A5"
cat > "$TMP/private-A5/ballot.json" <<'EOF'
{"voter":"A5","verdict":"FRAGILE","confidence":"medium","evidence":[],"concerns":["one edge case"],"notes":""}
EOF
python3 "$HERE/voting-harness.py" aggregate "$TMP" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
assert r['outcome'] == 'APPROVE_WITH_NOTES', f'expected APPROVE_WITH_NOTES got {r[\"outcome\"]}'
assert r['pass_count'] == 4
assert r['fail_count'] == 1
print('PASS: aggregate-4pass')
"
