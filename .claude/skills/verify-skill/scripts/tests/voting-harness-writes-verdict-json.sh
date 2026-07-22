#!/usr/bin/env bash
# Regression test: voting-harness.py aggregate writes verdict.json to
# $RUN_DIR by default (V4 gap fix from iter-3 e2e dogfood).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT

# Build 5 ballots (all PASS, standalone — should be APPROVE)
for n in 1 2 3 4 5; do
  mkdir -p "$TMP/private-A${n}"
done
cat > "$TMP/private-A1/ballot.json" <<EOF
{"voter":"A1-trigger","verdict":"TRIGGER_PASS","confidence":"high"}
EOF
cat > "$TMP/private-A2/ballot.json" <<EOF
{"voter":"A2-behavior","verdict":"BEHAVIOR_PASS","confidence":"high"}
EOF
cat > "$TMP/private-A3/ballot.json" <<EOF
{"voter":"A3-equivalence","verdict":"EQUIVALENT","confidence":"high"}
EOF
cat > "$TMP/private-A4/ballot.json" <<EOF
{"voter":"A4-contract","verdict":"CONTRACT_HELD","confidence":"high"}
EOF
cat > "$TMP/private-A5/ballot.json" <<EOF
{"voter":"A5-adversarial","verdict":"ROBUST","confidence":"high"}
EOF

# Default: should write verdict.json
python3 "$HERE/voting-harness.py" aggregate "$TMP" >/dev/null
test -f "$TMP/verdict.json" || { echo "FAIL: verdict.json not written by default"; exit 1; }
grep -q '"outcome": "APPROVE"' "$TMP/verdict.json" || { echo "FAIL: outcome not APPROVE"; cat "$TMP/verdict.json"; exit 1; }
echo "  ok: default writes verdict.json with APPROVE outcome"

# --output-file explicit path
out_path="$TMP/custom-verdict.json"
python3 "$HERE/voting-harness.py" aggregate "$TMP" --output-file "$out_path" >/dev/null
test -f "$out_path" || { echo "FAIL: --output-file did not write to custom path"; exit 1; }
echo "  ok: --output-file honored"

echo "PASS: voting-harness-writes-verdict-json (V4 gap fix)"
