#!/usr/bin/env bash
# Offline tests for quota-estimator.py — fixture ledgers, no network.
#
# Dates are PINNED via --date: fixtures never depend on the wall clock, so the
# suite cannot flake across a midnight rollover and needs no GNU-only `date -d`.
#
# Tests:
#   1. quota day: pressure 1.0, available false, capacity_floor from runs before quota
#   2. exact-key scoping: a sibling effort on the same backend+model stays available
#   3. no-quota day with history: pressure = runs_ok_today / p20(capacity_floor)
#   4. unknown capacity: pressure "N/A", never green/safe
#   5. api_equivalent_usd and usd_saved computed from tokens and actual cost
#   6. --format table renders one row per (backend, model, effort)
#   7. degenerate floor (quota first, zero capacity observed) is N/A, not 1.0-available
#   8. interleaved ledger order cannot manufacture a spurious zero floor
#   9. malformed ledger lines are skipped, not fatal
#  10. --date rejects a non-date

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EST="$SCRIPT_DIR/../quota-estimator.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TODAY="2026-07-27"
PREV1="2026-07-24"
PREV2="2026-07-23"

# rec <ts> <backend> <model> <effort> <quota> <in> <out> <cache_read> <cache_create> [cost_usd]
rec() {
  python3 -c '
import json, sys
ts, b, m, e, q, i, o, cr, cc = sys.argv[1:10]
cost = sys.argv[10] if len(sys.argv) > 10 else ""
print(json.dumps({
    "ts": ts, "backend": b, "model": m, "effort": e,
    "quota_exhausted": q == "1", "exit_code": 75 if q == "1" else 0,
    "in_tok": int(i), "out_tok": int(o),
    "cache_read": int(cr), "cache_create": int(cc),
    "latency_ms": 1200, "cost_usd": float(cost) if cost else None,
    "result": "" if q == "1" else "ok",
}))' "$@"
}

# --- Fixture: cursor/composer-2.5/none hit quota today after 2 OK runs.
#     Two prior quota days give capacity_floor history (4 and 6).
#     cursor/composer-2.5/high is a SIBLING key: no quota, must stay available.
#     claude/claude-haiku-4-5/low ran today with no history: unknown capacity.
LEDGER="$TMP/ledger.jsonl"
: > "$LEDGER"
for n in 1 2; do rec "${TODAY}T09:0${n}:00" cursor composer-2.5 none 0 1000 200 50 10 >> "$LEDGER"; done
rec "${TODAY}T09:30:00" cursor composer-2.5 none 1 0 0 0 0 >> "$LEDGER"
for n in 1 2 3 4; do rec "${PREV1}T09:0${n}:00" cursor composer-2.5 none 0 1000 200 50 10 >> "$LEDGER"; done
rec "${PREV1}T10:00:00" cursor composer-2.5 none 1 0 0 0 0 >> "$LEDGER"
for n in 1 2 3 4 5 6; do rec "${PREV2}T09:0${n}:00" cursor composer-2.5 none 0 1000 200 50 10 >> "$LEDGER"; done
rec "${PREV2}T10:00:00" cursor composer-2.5 none 1 0 0 0 0 >> "$LEDGER"
# sibling effort, same backend+model, no quota ever
rec "${TODAY}T09:05:00" cursor composer-2.5 high 0 1000 200 50 10 >> "$LEDGER"
# unknown-capacity channel: today only, no quota history anywhere.
# cost_usd 0.02 exercises usd_saved = api_equivalent - actual.
rec "${TODAY}T09:06:00" claude claude-haiku-4-5 low 0 3000 400 100 20 0.02 >> "$LEDGER"

report() { python3 "$EST" --ledger "$LEDGER" --date "$TODAY" --format json; }

# --- Test 1: quota day ---
if report | python3 -c '
import json, sys
d = {(r["backend"], r["model"], r["effort"]): r for r in json.load(sys.stdin)["channels"]}
r = d[("cursor", "composer-2.5", "none")]
assert r["pressure"] == 1.0, r["pressure"]
assert r["available"] is False, r
assert r["runs_quota"] == 1 and r["runs_ok"] == 2, r
assert r["capacity_floor"] == 2, r["capacity_floor"]
assert r["history_floors"] == [4, 6], r["history_floors"]
assert r["last_quota_at"].startswith(sys.argv[1]), r["last_quota_at"]
' "$TODAY"; then pass "quota day -> pressure 1.0, unavailable"; else fail "quota day -> pressure 1.0, unavailable"; fi

# --- Test 2: exact-key scoping ---
if report | python3 -c '
import json, sys
d = {(r["backend"], r["model"], r["effort"]): r for r in json.load(sys.stdin)["channels"]}
sib = d[("cursor", "composer-2.5", "high")]
assert sib["available"] is True, sib
assert sib["runs_quota"] == 0, sib
' ; then pass "sibling effort not marked unavailable"; else fail "sibling effort not marked unavailable"; fi

# --- Test 3: pressure from p20 of historical capacity_floor ---
# Today hits quota for composer-2.5/none, so pressure pins at 1.0 (test 1).
# Use a channel with history and NO quota today to exercise the ratio branch.
# History floors [4, 6] -> p20 = 4.4; runs_ok_today = 2 -> 2/4.4.
LEDGER2="$TMP/ledger2.jsonl"
: > "$LEDGER2"
for n in 1 2 3 4; do rec "${PREV1}T09:0${n}:00" codex gpt-5.3-codex medium 0 1000 200 50 10 >> "$LEDGER2"; done
rec "${PREV1}T10:00:00" codex gpt-5.3-codex medium 1 0 0 0 0 >> "$LEDGER2"
for n in 1 2 3 4 5 6; do rec "${PREV2}T09:0${n}:00" codex gpt-5.3-codex medium 0 1000 200 50 10 >> "$LEDGER2"; done
rec "${PREV2}T10:00:00" codex gpt-5.3-codex medium 1 0 0 0 0 >> "$LEDGER2"
for n in 1 2; do rec "${TODAY}T09:0${n}:00" codex gpt-5.3-codex medium 0 1000 200 50 10 >> "$LEDGER2"; done
if python3 "$EST" --ledger "$LEDGER2" --date "$TODAY" --format json | python3 -c '
import json, sys
r = json.load(sys.stdin)["channels"][0]
assert r["available"] is True, r
assert r["history_floors"] == [4, 6], r["history_floors"]
assert abs(r["pressure"] - 2 / 4.4) < 1e-9, r["pressure"]
'; then pass "no-quota day -> runs_ok_today / p20(capacity_floor)"; else fail "no-quota day -> runs_ok_today / p20(capacity_floor)"; fi

# --- Test 4: unknown capacity is N/A, never safe ---
if report | python3 -c '
import json, sys
d = {(r["backend"], r["model"], r["effort"]): r for r in json.load(sys.stdin)["channels"]}
r = d[("claude", "claude-haiku-4-5", "low")]
assert r["pressure"] == "N/A", r["pressure"]
assert r["capacity_floor"] is None, r
assert r["history_floors"] == [], r
assert r["available"] is True, r
'; then pass "unknown capacity -> N/A"; else fail "unknown capacity -> N/A"; fi

if python3 "$EST" --ledger "$LEDGER" --date "$TODAY" --format table \
   | grep -E 'claude-haiku-4-5' | grep -q 'N/A'; then
  pass "table shows N/A, not a number"; else fail "table shows N/A, not a number"; fi

# --- Test 5: api_equivalent_usd / usd_saved exact values ---
# 3000 in @ $3/M + 400 out @ $15/M + 100 cache_read @ $0.30/M
#   + 20 cache_create @ $3.75/M = 0.009 + 0.006 + 0.00003 + 0.000075 = 0.015105
# usd_saved = 0.015105 - 0.02 (actual) = -0.004895 — negative is meaningful:
# this run cost more than the incumbent would have.
if report | python3 -c '
import json, sys
d = {(r["backend"], r["model"], r["effort"]): r for r in json.load(sys.stdin)["channels"]}
r = d[("claude", "claude-haiku-4-5", "low")]
assert r["in_tok"] == 3000 and r["out_tok"] == 400, r
assert r["cache_read"] == 100 and r["cache_create"] == 20, r
assert r["api_equivalent_usd"] == 0.015105, r["api_equivalent_usd"]
assert r["cost_usd"] == 0.02, r["cost_usd"]
assert r["usd_saved"] == -0.004895, r["usd_saved"]
'; then pass "api_equivalent_usd and usd_saved exact"; else fail "api_equivalent_usd and usd_saved exact"; fi

# --- Test 6: table shape — one row per key, one field per column ---
out=$(python3 "$EST" --ledger "$LEDGER" --date "$TODAY" --format table)
if echo "$out" | python3 -c '
import sys
lines = [l for l in sys.stdin.read().splitlines() if l.strip()]
header = next(l for l in lines if l.startswith("backend"))
hi = lines.index(header)
cols = len(header.split())
# rows sit between the --- rule and the trailing notes
body = [l for l in lines[hi + 2:] if not l.startswith(("pressure", "api_usd"))]
assert len(body) == 3, f"expected 3 channel rows, got {len(body)}: {body}"
keys = {tuple(l.split()[:3]) for l in body}
assert keys == {
    ("cursor", "composer-2.5", "none"),
    ("cursor", "composer-2.5", "high"),
    ("claude", "claude-haiku-4-5", "low"),
}, keys
for l in body:
    assert len(l.split()) == cols, f"{cols} columns expected, got {len(l.split())}: {l}"
'; then pass "table renders one row per exact key"; else fail "table renders one row per exact key"; fi

# --- Test 7: degenerate floor -> unknown, never available-with-1.0 ---
# PREV1 opens with a quota event: zero successful runs observed, so that day
# yields floor 0. A zero floor is no observation at all, not "capacity zero".
LEDGER3="$TMP/ledger3.jsonl"
: > "$LEDGER3"
rec "${PREV1}T08:00:00" opencode github-copilot/claude-opus-4.6 low 1 0 0 0 0 >> "$LEDGER3"
for n in 1 2 3; do rec "${TODAY}T09:0${n}:00" opencode github-copilot/claude-opus-4.6 low 0 1000 200 50 10 >> "$LEDGER3"; done
if python3 "$EST" --ledger "$LEDGER3" --date "$TODAY" --format json | python3 -c '
import json, sys
r = json.load(sys.stdin)["channels"][0]
assert r["history_floors"] == [], r["history_floors"]
assert r["pressure"] == "N/A", r["pressure"]
'; then pass "degenerate zero floor -> N/A"; else fail "degenerate zero floor -> N/A"; fi

# --- Test 8: out-of-order ledger lines still yield the true floor ---
# Same day, quota at 10:00 after 3 OK runs, but written quota-line-first.
LEDGER4="$TMP/ledger4.jsonl"
: > "$LEDGER4"
rec "${PREV1}T10:00:00" cursor composer-2.5 none 1 0 0 0 0 >> "$LEDGER4"
rec "${PREV1}T09:03:00" cursor composer-2.5 none 0 1000 200 50 10 >> "$LEDGER4"
rec "${PREV1}T09:01:00" cursor composer-2.5 none 0 1000 200 50 10 >> "$LEDGER4"
rec "${PREV1}T09:02:00" cursor composer-2.5 none 0 1000 200 50 10 >> "$LEDGER4"
rec "${TODAY}T09:01:00" cursor composer-2.5 none 0 1000 200 50 10 >> "$LEDGER4"
if python3 "$EST" --ledger "$LEDGER4" --date "$TODAY" --format json | python3 -c '
import json, sys
r = json.load(sys.stdin)["channels"][0]
assert r["history_floors"] == [3], r["history_floors"]
assert abs(r["pressure"] - 1 / 3) < 1e-9, r["pressure"]
'; then pass "interleaved order -> true floor"; else fail "interleaved order -> true floor"; fi

# --- Test 9: malformed lines skipped, valid ones still counted ---
LEDGER5="$TMP/ledger5.jsonl"
{
  echo 'not json at all'
  echo '{"ts": "truncated"'
  echo 'null'
  echo '[]'
  echo '{"no_backend": true}'
  echo ''
  echo '   '
  rec "${TODAY}T09:01:00" cursor composer-2.5 none 0 1000 200 50 10
} > "$LEDGER5"
if python3 "$EST" --ledger "$LEDGER5" --date "$TODAY" --format json | python3 -c '
import json, sys
chans = json.load(sys.stdin)["channels"]
assert len(chans) == 1, chans
assert chans[0]["runs_ok"] == 1, chans[0]
'; then pass "malformed ledger lines skipped"; else fail "malformed ledger lines skipped"; fi

# --- Test 10: --date validation ---
if ! python3 "$EST" --ledger "$LEDGER" --date lolnope > /dev/null 2>&1; then
  pass "--date rejects non-date"; else fail "--date rejects non-date"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
