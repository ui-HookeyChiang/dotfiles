#!/usr/bin/env bash
# SC13 — main agent's deadline writer wins; late voter writes to ballot.late.json.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
PD="$TMP/private-A1"; mkdir -p "$PD"

# Simulate: main agent at deadline acquires lock + writes synthetic ballot
"$HERE/voter-lock.sh" acquire "$PD"
cat > "$PD/ballot.json" <<'EOF'
{"voter":"A1","verdict":"TIMEOUT_FAIL","confidence":"low","notes":"main_agent_deadline"}
EOF

# Voter arrives late
if "$HERE/voter-lock.sh" acquire "$PD" 2>/dev/null; then
  echo "FAIL: late voter acquired lock (should have lost)"; exit 1
fi
# Voter writes to ballot.late.json instead
cat > "$PD/ballot.late.json" <<'EOF'
{"voter":"A1","verdict":"TRIGGER_PASS","confidence":"high","notes":"voter completed but lock was held"}
EOF

# Aggregate must see TIMEOUT_FAIL, NOT TRIGGER_PASS
for i in 2 3 4 5; do
  mkdir -p "$TMP/private-A$i"
  cat > "$TMP/private-A$i/ballot.json" <<EOF
{"voter":"A$i","verdict":"BEHAVIOR_PASS","confidence":"medium","notes":""}
EOF
done
# Replace dummy verdicts with realistic
echo '{"voter":"A2","verdict":"BEHAVIOR_PASS","confidence":"medium"}' > "$TMP/private-A2/ballot.json"
echo '{"voter":"A3","verdict":"EQUIVALENT","confidence":"medium"}' > "$TMP/private-A3/ballot.json"
echo '{"voter":"A4","verdict":"CONTRACT_HELD","confidence":"medium"}' > "$TMP/private-A4/ballot.json"
echo '{"voter":"A5","verdict":"ROBUST","confidence":"medium"}' > "$TMP/private-A5/ballot.json"

python3 "$HERE/voting-harness.py" aggregate "$TMP" | python3 -c "
import json, sys
r = json.loads(sys.stdin.read())
# A1 TIMEOUT_FAIL counted as a FAIL; 4/5 PASS → APPROVE_WITH_NOTES (standalone)
assert r['outcome'] == 'APPROVE_WITH_NOTES', f'got {r[\"outcome\"]}'
assert r['fail_count'] == 1
print('PASS: timeout-late-arrival (aggregator ignored ballot.late.json)')
"
