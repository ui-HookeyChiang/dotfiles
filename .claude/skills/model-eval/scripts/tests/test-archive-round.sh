#!/usr/bin/env bash
# test-archive-round.sh — fixture test for archive-round.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE="$SCRIPT_DIR/../archive-round.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Setup: fake ledger
mkdir -p "$TMP/out"
cat > "$TMP/out/ledger.jsonl" <<'EOF'
{"q":"scan","model":"haiku","ts":"2026-07-28T10:00:00Z","result":"PASS"}
{"q":"execute","model":"sonnet","ts":"2026-07-28T11:00:00Z","result":"FAIL"}
{"q":"scan","model":"haiku","ts":"2026-07-28T12:00:00Z","result":"PASS"}
EOF

# Test 1: basic archive
MODEL_EVAL_OUT="$TMP/out" bash "$ARCHIVE" test-round --ledger "$TMP/out/ledger.jsonl" 2>/dev/null
evidence="$(find "$SCRIPT_DIR/../../evidence" -name "*test-round*" 2>/dev/null || find "$TMP" -name "*test-round*" 2>/dev/null)"
# archive writes relative to script — override via env
# Actually let's just test the output dir properly
rm -rf "$TMP/evidence"
EVIDENCE_OUT="$TMP/evidence"
# Re-run pointing at our tmp
(cd "$TMP" && MODEL_EVAL_OUT="$TMP/out" bash "$ARCHIVE" basic-round --ledger "$TMP/out/ledger.jsonl") 2>/dev/null
# The script writes to model-eval/evidence relative to itself, not cwd. So check there:
OUT_DIR="$SCRIPT_DIR/../../evidence"
FOUND=$(find "$OUT_DIR" -name "*basic-round*" 2>/dev/null | head -1)
if [ -n "$FOUND" ] && [ "$(wc -l < "$FOUND" | tr -d ' ')" = "3" ]; then
  pass "basic archive (3 rows)"
  rm -f "$FOUND"
else
  fail "basic archive: file=$FOUND"
fi

# Test 2: filter
MODEL_EVAL_OUT="$TMP/out" bash "$ARCHIVE" filtered-round --ledger "$TMP/out/ledger.jsonl" \
  --filter '.q=="scan"' 2>/dev/null
FOUND=$(find "$OUT_DIR" -name "*filtered-round*" 2>/dev/null | head -1)
if [ -n "$FOUND" ] && [ "$(wc -l < "$FOUND" | tr -d ' ')" = "2" ]; then
  pass "filtered archive (2 scan rows)"
  rm -f "$FOUND"
else
  fail "filtered archive: file=$FOUND, lines=$(wc -l < "${FOUND:-/dev/null}" 2>/dev/null)"
fi

# Test 3: refuse overwrite
mkdir -p "$OUT_DIR"
touch "$OUT_DIR/ledger-$(date +%Y-%m-%d)-existing-round.jsonl"
if MODEL_EVAL_OUT="$TMP/out" bash "$ARCHIVE" existing-round --ledger "$TMP/out/ledger.jsonl" 2>/dev/null; then
  fail "overwrite not refused"
else
  pass "refuses overwrite"
fi
rm -f "$OUT_DIR/ledger-$(date +%Y-%m-%d)-existing-round.jsonl"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
