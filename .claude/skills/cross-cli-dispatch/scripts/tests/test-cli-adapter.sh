#!/usr/bin/env bash
# Offline tests for cli-adapter.sh — stub binaries, no network.
#
# Tests:
#   1. claude backend: ledger line fields from canned claude JSON
#   2. cursor backend: effort becomes model-name suffix (argv assert)
#   3. cursor backend: pre-suffixed model NOT double-suffixed
#   4. quota error: exit 75, quota_exhausted true, channel marked in state
#   5. next-channel: skips quota-marked head, returns next
#   6. next-channel: all exhausted -> exit 3 JSON reason
#   7. next-channel: unknown tier -> exit 2
#   8. next-channel: unsupported row -> exit 3 JSON reason
#   9. next-channel: decide row selected; exhausted decide -> surface_to_user
#   10. detect-channels: skips absent backend and caches daily result
#   11. cursor detection can use `cursor-agent status` when no cred file exists
#   12. --allow: overrides detection include/exclude and can exclude API tail
#   13. codex backend: JSONL agent_message + token usage extraction
#   14. missing usage -> cost_estimated true
#   15. emitted record carries ISO-8601 UTC ts, and the estimator files it
#       under that day

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADAPTER="$SCRIPT_DIR/../cli-adapter.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

mkstub() { # $1=path $2=body
  printf '#!/bin/sh\n%s\n' "$2" > "$1"
  chmod +x "$1"
}

# --- Test 1: claude normalization ---
mkstub "$TMP/claude-ok" 'echo "{\"result\":\"PASS all 14\",\"num_turns\":3,\"total_cost_usd\":0.012,\"duration_api_ms\":900,\"usage\":{\"input_tokens\":100,\"output_tokens\":50,\"cache_creation_input_tokens\":1,\"cache_read_input_tokens\":2}}"'
line=$(CLI_ADAPTER_CLAUDE_BIN="$TMP/claude-ok" bash "$ADAPTER" run \
  --backend claude --model claude-haiku-4-5 --effort low \
  --prompt hi --run-dir "$TMP/r1" --tier scan)
rc=$?
if [ "$rc" -eq 0 ] && echo "$line" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read())
assert d["backend"]=="claude" and d["model"]=="claude-haiku-4-5"
assert d["result"].startswith("PASS") and d["out_tok"]==50 and d["in_tok"]==100
assert d["cost_usd"]==0.012 and d["cost_estimated"] is False
assert d["q"]=="scan" and d["quota_exhausted"] is False
'; then pass "claude normalization"; else fail "claude normalization"; fi

# --- Tests 2+3: cursor effort suffix ---
mkstub "$TMP/cursor-rec" "echo \"\$@\" > $TMP/cursor.argv; echo '{\"result\":\"ok\"}'"
CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-rec" bash "$ADAPTER" run \
  --backend cursor --model claude-opus-4-8 --effort low \
  --prompt hi --run-dir "$TMP/r2" > /dev/null
if grep -q -- '--model claude-opus-4-8-low' "$TMP/cursor.argv"; then
  pass "cursor effort suffix"; else fail "cursor effort suffix"; fi

CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-rec" bash "$ADAPTER" run \
  --backend cursor --model gpt-5.4-high --effort low \
  --prompt hi --run-dir "$TMP/r3" > /dev/null
if grep -q -- '--model gpt-5.4-high ' "$TMP/cursor.argv" \
   && ! grep -q 'gpt-5.4-high-low' "$TMP/cursor.argv"; then
  pass "no double suffix"; else fail "no double suffix"; fi

# --- Test 4: quota error path ---
mkstub "$TMP/cursor-quota" 'echo "Error: rate limit exceeded (429)" >&2; exit 1'
line=$(CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-quota" bash "$ADAPTER" run \
  --backend cursor --model claude-opus-4-8 --effort low --prompt hi \
  --run-dir "$TMP/r4" --state-dir "$TMP/state")
rc=$?
qf="$TMP/state/quota-$(date +%Y%m%d)"
if [ "$rc" -eq 75 ] \
   && echo "$line" | grep -q '"quota_exhausted": true' \
   && grep -qxF 'cursor,claude-opus-4-8,low' "$qf"; then
  pass "quota -> exit 75 + state mark"; else fail "quota -> exit 75 + state mark (rc=$rc)"; fi

# --- Tests 5-9: next-channel ---
printf 'execute	cursor,claude-opus-4-8,low;codex,gpt-5.3-codex,medium;claude,claude-haiku-4-5,low
decide	claude,claude-opus-4-6,low
never	unsupported
' > "$TMP/bindings.tsv"
mkdir -p "$TMP/state2"
echo 'cursor,claude-opus-4-8,low' > "$TMP/state2/quota-$(date +%Y%m%d)"
got=$(bash "$ADAPTER" next-channel --tier execute \
  --bindings "$TMP/bindings.tsv" --state-dir "$TMP/state2" --allow cursor,codex,claude)
if [ "$got" = "$(printf 'codex\tgpt-5.3-codex\tmedium')" ]; then
  pass "next-channel skips exhausted"; else fail "next-channel skips exhausted (got: $got)"; fi

printf 'cursor,claude-opus-4-8,low\ncodex,gpt-5.3-codex,medium\nclaude,claude-haiku-4-5,low\n' \
  > "$TMP/state2/quota-$(date +%Y%m%d)"
got=$(bash "$ADAPTER" next-channel --tier execute \
  --bindings "$TMP/bindings.tsv" --state-dir "$TMP/state2" --allow cursor,codex,claude)
rc=$?
if [ "$rc" -eq 3 ] && echo "$got" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["tier"]=="execute" and d["reason"]=="channel_exhausted" and d["action"]=="retry"'; then
  pass "all exhausted -> exit 3 JSON"; else fail "all exhausted -> exit 3 JSON (rc=$rc got: $got)"; fi

bash "$ADAPTER" next-channel --tier nosuch --bindings "$TMP/bindings.tsv" \
  --state-dir "$TMP/state2" 2>/dev/null
if [ $? -eq 2 ]; then pass "unknown tier exit 2"; else fail "unknown tier exit 2"; fi

got=$(bash "$ADAPTER" next-channel --tier never \
  --bindings "$TMP/bindings.tsv" --state-dir "$TMP/state2" --allow cursor,codex,claude)
rc=$?
if [ "$rc" -eq 3 ] && echo "$got" | grep -q '"reason":"unsupported"'; then
  pass "unsupported row exit 3"; else fail "unsupported row exit 3 (rc=$rc got: $got)"; fi

got=$(bash "$ADAPTER" next-channel --tier decide \
  --bindings "$TMP/bindings.tsv" --state-dir "$TMP/state2" --allow cursor,codex,claude)
if [ "$got" = "$(printf 'claude\tclaude-opus-4-6\tlow')" ]; then
  pass "decide row selected"; else fail "decide row selected (got: $got)"; fi

echo 'claude,claude-opus-4-6,low' >> "$TMP/state2/quota-$(date +%Y%m%d)"
got=$(bash "$ADAPTER" next-channel --tier decide \
  --bindings "$TMP/bindings.tsv" --state-dir "$TMP/state2" --allow cursor,codex,claude)
rc=$?
if [ "$rc" -eq 3 ] && echo "$got" | grep -q '"action":"surface_to_user"'; then
  pass "decide exhausted -> surface_to_user"; else fail "decide exhausted -> surface_to_user (rc=$rc got: $got)"; fi

# --- Tests 10-11: detection and allow filtering ---
printf 'execute	cursor,missing-cursor,none;codex,gpt-5.3-codex,medium;claude,claude-haiku-4-5,low
' > "$TMP/detect-bindings.tsv"
mkstub "$TMP/codex-detect" 'echo should-not-run'
: > "$TMP/codex.cred"
got=$(HOME="$TMP/empty-home" CLI_ADAPTER_CURSOR_BIN="$TMP/missing-cursor" \
  CLI_ADAPTER_CODEX_BIN="$TMP/codex-detect" CLI_ADAPTER_CODEX_CRED="$TMP/codex.cred" \
  bash "$ADAPTER" next-channel --tier execute \
  --bindings "$TMP/detect-bindings.tsv" --state-dir "$TMP/state3")
if [ "$got" = "$(printf 'codex\tgpt-5.3-codex\tmedium')" ]; then
  pass "detect skips absent backend"; else fail "detect skips absent backend (got: $got)"; fi

rm -f "$TMP/codex-detect" "$TMP/codex.cred"
got=$(HOME="$TMP/empty-home" CLI_ADAPTER_CURSOR_BIN="$TMP/missing-cursor" \
  CLI_ADAPTER_CODEX_BIN="$TMP/codex-detect" CLI_ADAPTER_CODEX_CRED="$TMP/codex.cred" \
  bash "$ADAPTER" detect-channels --state-dir "$TMP/state3")
if [ "$got" = codex ]; then
  pass "detect cache reused"; else fail "detect cache reused (got: $got)"; fi

mkstub "$TMP/cursor-status-ok" 'if [ "$1" = status ]; then echo "logged in"; exit 0; fi; exit 1'
got=$(HOME="$TMP/empty-home" CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-status-ok" \
  CLI_ADAPTER_CURSOR_CRED="$TMP/missing-cursor.cred" \
  bash "$ADAPTER" detect-channels --state-dir "$TMP/state_cursor_status")
if [ "$got" = cursor ]; then
  pass "cursor detect via status"; else fail "cursor detect via status (got: $got)"; fi

rm -rf "$TMP/state4"
got=$(bash "$ADAPTER" next-channel --tier execute \
  --bindings "$TMP/detect-bindings.tsv" --state-dir "$TMP/state4" --allow codex)
if [ "$got" = "$(printf 'codex\tgpt-5.3-codex\tmedium')" ]; then
  pass "allow includes undetected backend"; else fail "allow includes undetected backend (got: $got)"; fi

mkdir -p "$TMP/state4"
printf 'cursor,missing-cursor,none\n' > "$TMP/state4/quota-$(date +%Y%m%d)"
got=$(bash "$ADAPTER" next-channel --tier execute \
  --bindings "$TMP/detect-bindings.tsv" --state-dir "$TMP/state4" --allow cursor)
rc=$?
if [ "$rc" -eq 3 ] && echo "$got" | grep -q '"reason":"channel_exhausted"'; then
  pass "allow excludes API tail"; else fail "allow excludes API tail (rc=$rc got: $got)"; fi

# --- Test 12: codex JSONL ---
mkstub "$TMP/codex-ok" 'printf "%s\n" \
  "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"answer here\"}}" \
  "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":200,\"output_tokens\":80,\"cached_input_tokens\":10}}"'
line=$(CLI_ADAPTER_CODEX_BIN="$TMP/codex-ok" bash "$ADAPTER" run \
  --backend codex --model gpt-5.3-codex --effort medium \
  --prompt hi --run-dir "$TMP/r5")
if echo "$line" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read())
assert d["result"]=="answer here" and d["out_tok"]==80 and d["in_tok"]==200
assert d["cost_estimated"] is False
'; then pass "codex JSONL parse"; else fail "codex JSONL parse"; fi

# --- Test 13: missing usage -> cost_estimated ---
mkstub "$TMP/oc-nousage" 'printf "%s\n" \
  "{\"type\":\"text\",\"part\":{\"type\":\"text\",\"text\":\"done\"}}" \
  "{\"type\":\"step_finish\",\"part\":{\"reason\":\"stop\"}}"'
line=$(CLI_ADAPTER_OPENCODE_BIN="$TMP/oc-nousage" bash "$ADAPTER" run \
  --backend opencode --model github-copilot/claude-opus-4.6 --effort low \
  --prompt hi --run-dir "$TMP/r6")
if echo "$line" | grep -q '"cost_estimated": true'; then
  pass "absent usage -> cost_estimated"; else fail "absent usage -> cost_estimated"; fi

# --- Test 14: cursor camelCase usage keys ---
# cursor-agent 2026-07-27 emits inputTokens/outputTokens/cacheReadTokens/
# cacheWriteTokens, not the snake_case spelling the other backends use.
mkstub "$TMP/cursor-usage" 'echo "{\"type\":\"result\",\"result\":\"ok\",\"duration_api_ms\":7999,\"usage\":{\"inputTokens\":37777,\"outputTokens\":18,\"cacheReadTokens\":5,\"cacheWriteTokens\":7}}"'
line=$(CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-usage" bash "$ADAPTER" run \
  --backend cursor --model gpt-5.5-low --effort none \
  --prompt hi --run-dir "$TMP/r7")
if echo "$line" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read())
assert d["in_tok"]==37777 and d["out_tok"]==18, d
assert d["cache_read"]==5 and d["cache_create"]==7, d
assert d["api_ms"]==7999, d
assert d["cost_estimated"] is False, d
'; then pass "cursor camelCase usage"; else fail "cursor camelCase usage"; fi

# --- Test 15: cursor snake_case usage keys still parse ---
# Guards the tok() fallback order: a cursor release that normalizes to the
# snake_case spelling other backends use must not regress.
mkstub "$TMP/cursor-snake" 'echo "{\"type\":\"result\",\"result\":\"ok\",\"duration_api_ms\":120,\"usage\":{\"input_tokens\":11,\"output_tokens\":22,\"cache_read_input_tokens\":3,\"cache_creation_input_tokens\":4}}"'
line=$(CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-snake" bash "$ADAPTER" run \
  --backend cursor --model gpt-5.5-low --effort none \
  --prompt hi --run-dir "$TMP/r8")
if echo "$line" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read())
assert d["in_tok"]==11 and d["out_tok"]==22, d
assert d["cache_read"]==3 and d["cache_create"]==4, d
assert d["cost_estimated"] is False, d
'; then pass "cursor snake_case usage"; else fail "cursor snake_case usage"; fi

# --- Test 16: emitted ts is ISO-8601 UTC and buckets in the estimator ---
# End-to-end through the real emit path: adapter run -> ledger line ->
# quota-estimator. Guards the contract the estimator's day bucketing needs.
mkstub "$TMP/claude-ts" 'echo "{\"result\":\"ok\",\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}"'
line=$(CLI_ADAPTER_CLAUDE_BIN="$TMP/claude-ts" bash "$ADAPTER" run \
  --backend claude --model claude-haiku-4-5 --effort low \
  --prompt hi --run-dir "$TMP/r9")
if echo "$line" | python3 -c '
import json, sys
from datetime import datetime, timezone
d = json.loads(sys.stdin.read())
ts = d["ts"]
assert ts.endswith("+00:00"), ts
parsed = datetime.fromisoformat(ts)
assert parsed.tzinfo is not None, ts
delta = abs((datetime.now(timezone.utc) - parsed).total_seconds())
assert delta < 300, f"ts not close to now: {ts}"
'; then pass "emitted record carries UTC ts"; else fail "emitted record carries UTC ts"; fi

echo "$line" > "$TMP/emitted.jsonl"
day=$(echo "$line" | python3 -c '
import json, sys
from datetime import datetime
print(datetime.fromisoformat(json.loads(sys.stdin.read())["ts"]).date().isoformat())')
if python3 "$SCRIPT_DIR/../quota-estimator.py" --ledger "$TMP/emitted.jsonl" \
     --date "$day" --format json | python3 -c '
import json, sys
chans = json.load(sys.stdin)["channels"]
assert len(chans) == 1, chans
assert chans[0]["runs_ok"] == 1, chans[0]
assert (chans[0]["backend"], chans[0]["model"], chans[0]["effort"]) == (
    "claude", "claude-haiku-4-5", "low"), chans[0]
'; then pass "estimator files emitted ts under its day"; else fail "estimator files emitted ts under its day"; fi

# --- Test 15: invalid effort rejected ---
if bash "$ADAPTER" run --backend claude --model x --effort xhigh --prompt hi \
   --run-dir "$TMP/r_bad_effort" 2>"$TMP/err_effort"; then
  fail "invalid effort accepted"
elif grep -q "invalid effort" "$TMP/err_effort"; then
  pass "invalid effort rejected"
else
  fail "invalid effort wrong message: $(cat "$TMP/err_effort")"
fi

# --- Test 16: cursor per-family effort map ---
mkstub "$TMP/cursor-rec2" "echo \"\$@\" > $TMP/cursor2.argv; echo '{\"result\":\"ok\"}'"
CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-rec2" \
CURSOR_EFFORT_MAP="$SCRIPT_DIR/../../data/cursor-effort-map.tsv" \
bash "$ADAPTER" run \
  --backend cursor --model gpt-5.4 --effort high \
  --prompt hi --run-dir "$TMP/r_map1" > /dev/null
if grep -q -- '--model gpt-5.4-xhigh' "$TMP/cursor2.argv"; then
  pass "cursor effort map gpt-5.4 high→xhigh"
else
  fail "cursor effort map gpt-5.4: $(cat "$TMP/cursor2.argv")"
fi

CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-rec2" \
CURSOR_EFFORT_MAP="$SCRIPT_DIR/../../data/cursor-effort-map.tsv" \
bash "$ADAPTER" run \
  --backend cursor --model gpt-5.5 --effort high \
  --prompt hi --run-dir "$TMP/r_map2" > /dev/null
if grep -q -- '--model gpt-5.5-extra-high' "$TMP/cursor2.argv"; then
  pass "cursor effort map gpt-5.5 high→extra-high"
else
  fail "cursor effort map gpt-5.5: $(cat "$TMP/cursor2.argv")"
fi

# Identity case: unlisted family uses canonical label
CLI_ADAPTER_CURSOR_BIN="$TMP/cursor-rec2" \
CURSOR_EFFORT_MAP="$SCRIPT_DIR/../../data/cursor-effort-map.tsv" \
bash "$ADAPTER" run \
  --backend cursor --model claude-opus-4-8 --effort medium \
  --prompt hi --run-dir "$TMP/r_map3" > /dev/null
if grep -q -- '--model claude-opus-4-8-medium' "$TMP/cursor2.argv"; then
  pass "cursor effort map identity fallback"
else
  fail "cursor effort map identity: $(cat "$TMP/cursor2.argv")"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
