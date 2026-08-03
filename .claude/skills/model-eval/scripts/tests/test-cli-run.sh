#!/usr/bin/env bash
# Offline tests for cli-run.sh — stub binaries, no network.
#
# Tests:
#   1. claude passthrough: writes valid claude.json (result, usage fields)
#   2. MODEL_EVAL_CLI=cursor: converts adapter ledger line to claude.json shape
#   3. exit 75 propagates from adapter

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_RUN="$SCRIPT_DIR/../cli-run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

mkstub() { # $1=path $2=body
  printf '#!/bin/sh\n%s\n' "$2" > "$1"
  chmod +x "$1"
}

# --- Test 1: claude passthrough writes valid claude.json ---
mkstub "$TMP/claude-ok" 'echo "{\"result\":\"hello world\",\"num_turns\":2,\"total_cost_usd\":0.005,\"duration_api_ms\":500,\"usage\":{\"input_tokens\":80,\"output_tokens\":30,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":5}}"'
OUT1="$TMP/out1.json"
echo "test prompt" | MODEL_EVAL_CLAUDE_BIN="$TMP/claude-ok" \
  sh "$CLI_RUN" "claude-haiku-4-5" "low" "4" "$OUT1"
rc=$?
if [ "$rc" -eq 0 ] && python3 -c "
import json, sys
d = json.load(open('$OUT1'))
assert d.get('result') == 'hello world', 'result mismatch'
assert d.get('num_turns') == 2, 'num_turns mismatch'
assert d.get('total_cost_usd') == 0.005, 'cost mismatch'
assert d.get('usage', {}).get('input_tokens') == 80, 'in_tok mismatch'
assert d.get('usage', {}).get('output_tokens') == 30, 'out_tok mismatch'
assert d.get('usage', {}).get('cache_read_input_tokens') == 5, 'cache_read mismatch'
" 2>/dev/null; then
  pass "claude passthrough writes valid claude.json"
else
  fail "claude passthrough writes valid claude.json (rc=$rc)"
fi

# --- Test 2: MODEL_EVAL_CLI=cursor converts adapter ledger line to claude.json shape ---
LEDGER_LINE='{"backend":"cursor","model":"claude-opus-4-8-low","result":"answer text","num_turns":3,"cost_usd":0.010,"api_ms":800,"in_tok":120,"out_tok":45,"cache_create":2,"cache_read":8,"quota_exhausted":false}'
mkstub "$TMP/fake-adapter" "printf '%s\n' '$LEDGER_LINE'"

OUT2="$TMP/out2.json"
mkdir -p "$TMP/fake-repo/cross-cli-dispatch/scripts"
cp "$TMP/fake-adapter" "$TMP/fake-repo/cross-cli-dispatch/scripts/cli-adapter.sh"
mkdir -p "$TMP/fake-repo/model-eval/scripts"
cp "$CLI_RUN" "$TMP/fake-repo/model-eval/scripts/cli-run.sh"

echo "test prompt" | MODEL_EVAL_CLI=cursor \
  sh "$TMP/fake-repo/model-eval/scripts/cli-run.sh" "claude-opus-4-8" "low" "4" "$OUT2"
rc=$?
if [ "$rc" -eq 0 ] && python3 -c "
import json
d = json.load(open('$OUT2'))
assert d.get('result') == 'answer text', 'result: ' + str(d.get('result'))
assert d.get('num_turns') == 3, 'num_turns: ' + str(d.get('num_turns'))
assert d.get('total_cost_usd') == 0.010, 'cost: ' + str(d.get('total_cost_usd'))
assert d.get('duration_api_ms') == 800, 'api_ms: ' + str(d.get('duration_api_ms'))
u = d.get('usage', {})
assert u.get('input_tokens') == 120, 'in_tok: ' + str(u.get('input_tokens'))
assert u.get('output_tokens') == 45, 'out_tok: ' + str(u.get('output_tokens'))
assert u.get('cache_creation_input_tokens') == 2
assert u.get('cache_read_input_tokens') == 8
" 2>&1; then
  pass "cursor backend converts ledger line to claude.json shape"
else
  fail "cursor backend converts ledger line to claude.json shape (rc=$rc)"
fi

# --- Test 3: exit 75 propagates ---
mkstub "$TMP/fake-quota-adapter" 'echo "{\"quota_exhausted\":true}" && exit 75'
mkdir -p "$TMP/fake-quota-repo/cross-cli-dispatch/scripts"
cp "$TMP/fake-quota-adapter" "$TMP/fake-quota-repo/cross-cli-dispatch/scripts/cli-adapter.sh"
mkdir -p "$TMP/fake-quota-repo/model-eval/scripts"
cp "$CLI_RUN" "$TMP/fake-quota-repo/model-eval/scripts/cli-run.sh"

OUT3="$TMP/out3.json"
echo "test prompt" | MODEL_EVAL_CLI=cursor \
  sh "$TMP/fake-quota-repo/model-eval/scripts/cli-run.sh" "some-model" "low" "4" "$OUT3"
rc=$?
if [ "$rc" -eq 75 ]; then
  pass "exit 75 propagates from adapter"
else
  fail "exit 75 propagates from adapter (got rc=$rc)"
fi

# --- Test 4: auto-resolve backend from inventory.tsv ---
# Create a fake repo with inventory that maps test-model → cursor
mkdir -p "$TMP/fake-inv-repo/cross-cli-dispatch/scripts" "$TMP/fake-inv-repo/model-eval/scripts"
printf 'cursor\ttest-cursor-model\n' > "$TMP/fake-inv-repo/cross-cli-dispatch/inventory.tsv"
LEDGER_LINE4='{"backend":"cursor","model":"test-cursor-model","result":"auto resolved"}'
mkstub "$TMP/fake-inv-adapter" "printf '%s\n' '$LEDGER_LINE4'"
cp "$TMP/fake-inv-adapter" "$TMP/fake-inv-repo/cross-cli-dispatch/scripts/cli-adapter.sh"
cp "$CLI_RUN" "$TMP/fake-inv-repo/model-eval/scripts/cli-run.sh"

OUT4="$TMP/out4.json"
echo "test" | sh "$TMP/fake-inv-repo/model-eval/scripts/cli-run.sh" "test-cursor-model" "low" "4" "$OUT4" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ] && python3 -c "
import json
d = json.load(open('$OUT4'))
assert d.get('result') == 'auto resolved', d
" 2>/dev/null; then
  pass "auto-resolve backend from inventory.tsv"
else
  fail "auto-resolve backend from inventory.tsv (rc=$rc)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
