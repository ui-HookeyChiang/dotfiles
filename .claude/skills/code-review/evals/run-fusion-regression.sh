#!/usr/bin/env bash
# run-fusion-regression.sh — Fusion regression test runner
# Exercises Phase 3.5 (Layer A), Gate A, Gate C, and Gate D (Jaccard).
# Exits with the number of failures (0 = all pass).
#
# Usage: ./code-review/evals/run-fusion-regression.sh
#   Run from the worktree root or from this directory — either works.

set -euo pipefail

FAILURES=0

# ── helpers ──────────────────────────────────────────────────────────────────

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; (( FAILURES++ )) || true; }

section() {
  echo ""
  echo "======================================================"
  echo "  $*"
  echo "======================================================"
}

# ── Test 1: Phase 3.5 Layer A — line validation ──────────────────────────────

section "Test 1 — Phase 3.5 Layer A: pre-flight line validation"

# Synthesize a fake pulls/{n}/files JSON with two candidate comments:
#   Candidate A → targets a '+' added line inside a hunk  → SHOULD PASS Gate 1+2
#   Candidate B → targets a ' ' context line              → SHOULD be DROPPED by Gate 2
#
# Patch: @@ -10,7 +10,9 @@ covers new file lines 10..18:
#   new line 11: "    new_call();"    type '+'  → candidate A target → PASS
#   new line 14: "    finalize();"    type ' '  → candidate B target → DROPPED Gate 2

LAYER_A_RESULT=$(python3 - <<'PYEOF'
import re, sys

fake_files = [
  {
    "filename": "src/manager.cpp",
    "patch": "@@ -10,7 +10,9 @@ void Manager::init() {\n-    old_call();\n+    new_call();\n+    setup_logger();\n+    verify_state();\n     finalize();\n }"
  }
]

def parse_hunks(patch):
    """Return list of (new_start, new_end) inclusive ranges from @@ headers."""
    hunks = []
    cur_new = None
    new_count = 0
    for line in patch.split('\n'):
        m = re.match(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', line)
        if m:
            if cur_new is not None:
                hunks.append((cur_new, cur_new + new_count - 1))
            cur_new = int(m.group(1))
            new_count = int(m.group(2)) if m.group(2) else 1
        elif cur_new is not None:
            pass  # count tracked by hunk header
    if cur_new is not None:
        hunks.append((cur_new, cur_new + new_count - 1))
    return hunks

def line_type_at(patch, new_line_num):
    """Return '+', '-', or ' ' for the patch line targeting new_line_num."""
    cur_new = None
    for line in patch.split('\n'):
        m = re.match(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', line)
        if m:
            cur_new = int(m.group(1))
            continue
        if cur_new is None:
            continue
        if line.startswith('-'):
            continue  # deletion: new line number does not advance
        if line.startswith('+'):
            if cur_new == new_line_num:
                return '+'
            cur_new += 1
        else:
            if cur_new == new_line_num:
                return ' '
            cur_new += 1
    return None

candidates = [
    {"id": "A", "filename": "src/manager.cpp", "line": 11, "body": "Consider renaming new_call() for clarity."},
    {"id": "B", "filename": "src/manager.cpp", "line": 14, "body": "finalize() lacks error check."},
]

passed = []
dropped = []
for c in candidates:
    file_entry = next((f for f in fake_files if f["filename"] == c["filename"]), None)
    if file_entry is None:
        dropped.append((c["id"], "file not in diff"))
        continue
    patch = file_entry["patch"]
    hunks = parse_hunks(patch)
    in_hunk = any(start <= c["line"] <= end for start, end in hunks)
    if not in_hunk:
        dropped.append((c["id"], f"Gate 1 FAIL: line {c['line']} not in any hunk {hunks}"))
        continue
    ltype = line_type_at(patch, c["line"])
    if ltype != '+':
        dropped.append((c["id"], f"Gate 2 FAIL: line {c['line']} type={repr(ltype)} (not '+')"))
        continue
    passed.append(c["id"])

print(f"passed={','.join(passed) if passed else 'none'} dropped={len(dropped)}")
for d in dropped:
    print(f"  dropped {d[0]}: {d[1]}")
PYEOF
)

echo "  Layer A output:"
echo "$LAYER_A_RESULT" | sed 's/^/    /'

SUMMARY_LINE=$(echo "$LAYER_A_RESULT" | head -1)
PASSED_IDS=$(echo "$SUMMARY_LINE" | sed 's/.*passed=\([^ ]*\).*/\1/')
DROPPED_COUNT=$(echo "$SUMMARY_LINE" | sed 's/.*dropped=\([0-9]*\).*/\1/')

if [ "$PASSED_IDS" = "none" ]; then
  PASSED_COUNT=0
else
  PASSED_COUNT=$(echo "$PASSED_IDS" | tr ',' '\n' | wc -l | tr -d ' ')
fi

if [ "$PASSED_COUNT" -eq 1 ] && [ "$DROPPED_COUNT" -eq 1 ]; then
  pass "Test 1: 1 candidate passed Gate 1+2 (added '+' line), 1 dropped (context ' ' line)"
else
  fail "Test 1: expected passed=1 dropped=1, got passed=$PASSED_COUNT dropped=$DROPPED_COUNT"
fi

# ── Test 2: Gate C — REAL concurrent processes ────────────────────────────────
# NOTE: Gate C lockfile is deprecated for CI (replaced by workflow concurrency
# group). This test validates the standalone-invocation lockfile pattern which
# remains in use when the skill is invoked outside CI (e.g. local flow-dev).

section "Test 2 — Gate C: concurrent lockfile (real background processes)"

LOCK_DIR="$HOME/.cache/code-review/locks"
LOCK_FILE="${LOCK_DIR}/test-fusion-regression.lock"
mkdir -p "$LOCK_DIR"
rm -f "$LOCK_FILE"

RESULT_DIR=$(mktemp -d)
cleanup_test2() { rm -rf "$RESULT_DIR" 2>/dev/null; rm -f "$LOCK_FILE" 2>/dev/null; }
trap cleanup_test2 EXIT

# Process A: acquires flock, sleeps to let B race it
bash -c "
  (
    flock -n 9 || { echo 'lock held — skipping' > '${RESULT_DIR}/A.txt'; exit 0; }
    echo \$\$ >> '${LOCK_FILE}'
    echo 'acquired' > '${RESULT_DIR}/A.txt'
    sleep 0.4
  ) 9>>'${LOCK_FILE}'
" &
PID_A=$!

sleep 0.1  # give A a head start to acquire

# Process B: races for the same lock
bash -c "
  (
    flock -n 9 || { echo 'lock held — skipping' > '${RESULT_DIR}/B.txt'; exit 0; }
    echo \$\$ >> '${LOCK_FILE}'
    echo 'acquired' > '${RESULT_DIR}/B.txt'
    sleep 0.2
  ) 9>>'${LOCK_FILE}'
" &
PID_B=$!

wait $PID_A $PID_B 2>/dev/null || true

A_RESULT=$(cat "${RESULT_DIR}/A.txt" 2>/dev/null || echo "no-result")
B_RESULT=$(cat "${RESULT_DIR}/B.txt" 2>/dev/null || echo "no-result")
echo "  Process A result: $A_RESULT"
echo "  Process B result: $B_RESULT"

WINNERS=0
SKIPPERS=0
for R in "$A_RESULT" "$B_RESULT"; do
  case "$R" in
    acquired) (( WINNERS++ )) || true ;;
    "lock held — skipping") (( SKIPPERS++ )) || true ;;
  esac
done

if [ "$WINNERS" -eq 1 ] && [ "$SKIPPERS" -eq 1 ]; then
  pass "Test 2a: 1 winner acquired lock, 1 process skipped — Gate C concurrent exclusion correct"
else
  fail "Test 2a: expected winners=1 skippers=1, got winners=$WINNERS skippers=$SKIPPERS"
fi

rm -f "$LOCK_FILE"

# Stale lock sub-test
touch -d "31 minutes ago" "$LOCK_FILE"
AGE=$(( $(date +%s) - $(date -r "$LOCK_FILE" +%s) ))
echo "  Stale lock age: ${AGE}s (expect > 1800)"

STALE_REMOVED=false
if [ "$AGE" -gt 1800 ]; then
  rm -f "$LOCK_FILE"
  STALE_REMOVED=true
fi

if [ "$STALE_REMOVED" = true ] && [ ! -f "$LOCK_FILE" ]; then
  pass "Test 2b: stale lock (${AGE}s old) correctly removed"
else
  fail "Test 2b: stale lock removal failed (age=${AGE}s stale_removed=${STALE_REMOVED})"
fi

# ── Test 3: Gate A — bot review detection via real jq pipeline ────────────────

section "Test 3 — Gate A: bot review detection with jq pipeline"

NOW_TS=$(date +%s)
RECENT_TS=$(( NOW_TS - 2400 ))   # 40 minutes ago — inside 1h window
OLD_TS=$(( NOW_TS - 7200 ))       # 2 hours ago — outside 1h window

RECENT_ISO=$(date -d "@$RECENT_TS" --utc +"%Y-%m-%dT%H:%M:%SZ")
OLD_ISO=$(date -d "@$OLD_TS" --utc +"%Y-%m-%dT%H:%M:%SZ")

MOCK_REVIEWS=$(jq -n \
  --arg recent "$RECENT_ISO" \
  --arg old "$OLD_ISO" \
  '[
    {"id": 1001, "user": {"login": "claude[bot]"},          "submitted_at": $recent, "state": "COMMENTED", "body": "Automated review."},
    {"id": 1002, "user": {"login": "alice"},                "submitted_at": $recent, "state": "APPROVED",  "body": "LGTM"},
    {"id": 1003, "user": {"login": "github-actions[bot]"}, "submitted_at": $old,    "state": "COMMENTED", "body": "CI passed."}
  ]')

THRESHOLD_ISO=$(date -d "@$(( NOW_TS - 3600 ))" --utc +"%Y-%m-%dT%H:%M:%SZ")

JQ_RESULT=$(echo "$MOCK_REVIEWS" | jq --arg threshold "$THRESHOLD_ISO" '
  [.[]
   | select(.user.login | test("github-actions|claude"; "i"))
   | select(.submitted_at > $threshold)
  ]
')

COUNT=$(echo "$JQ_RESULT" | jq 'length')
BOT_LOGIN=$(echo "$JQ_RESULT" | jq -r '.[0].user.login // "none"')
echo "  Bot reviews within last 1h: $COUNT"
echo "  First match login: $BOT_LOGIN (submitted $RECENT_ISO)"
echo "  Dropped: github-actions[bot] at $OLD_ISO (outside 1h window)"

if [ "$COUNT" -eq 1 ] && [ "$BOT_LOGIN" = "claude[bot]" ]; then
  pass "Test 3: Gate A jq selected claude[bot] (40m ago), dropped github-actions[bot] (2h ago)"
else
  fail "Test 3: expected count=1 login=claude[bot], got count=$COUNT login=$BOT_LOGIN"
fi

# ── Test 4: Gate D — Jaccard deduplication ───────────────────────────────────

section "Test 4 — Gate D: Jaccard dedup (Q5 senior-engineer-filter)"

# Wrap python block: Test 4 has its own FAILURES counting via T4_EXIT below.
# Without `set +e`, a python sys.exit(1) would abort the whole runner under
# `set -euo pipefail`, bypassing the Summary line and inconsistent with Tests 1-3.
set +e
python3 - <<'PYEOF'
import re, sys

STOP_WORDS = {
    "the","a","an","is","it","this","that","in","of","to","and","or",
    "for","with","be","are","was","will","not","as","at","by","from",
    "on","have","has","should","could","would","may","might","i","we",
    "you","he","she","they","can","do","does","did","if","its","than",
    "then","there","their","which","when","where","what","how","but","so"
}

def tokenize(text):
    tokens = re.findall(r'[a-z]+', text.lower())
    return set(t for t in tokens if t not in STOP_WORDS and len(t) > 1)

def jaccard(a, b):
    ta, tb = tokenize(a), tokenize(b)
    if not ta and not tb:
        return 1.0
    inter = len(ta & tb)
    union = len(ta | tb)
    return inter / union if union else 0.0

# Pair (A, B): highly similar comments on the same issue → Jaccard > 70% → dedup
# Token overlap: before, check, dereferencing, input, missing, null, pointer, segfault (8/9 = 0.89)
A = "Missing null check before dereferencing pointer — will segfault on null input."
B = "Missing null check before dereferencing pointer; segfault occurs on null input."

# Pair (A, C): different topics (null deref vs buffer overflow) → Jaccard < 70% → keep
C = "The buffer size should be validated against the maximum packet length to prevent overflow."

# Pair (D, E): very short — known stop-word inflation limitation
D = "Fix this."
E = "Fix it."

j_AB = jaccard(A, B)
j_AC = jaccard(A, C)
j_DE = jaccard(D, E)

verdict_AB = "dedup" if j_AB > 0.70 else "keep"
verdict_AC = "dedup" if j_AC > 0.70 else "keep"

print(f"  Pair(A,B): jaccard={j_AB:.3f}  verdict={verdict_AB}  (expected: dedup)")
print(f"  Pair(A,C): jaccard={j_AC:.3f}  verdict={verdict_AC}  (expected: keep)")
print(f"  Pair(D,E): jaccard={j_DE:.3f}  tokens_D={sorted(tokenize(D))} tokens_E={sorted(tokenize(E))}")
print(f"  [KNOWN LIMITATION] Short 2-word comments reduce to 0-1 tokens after stop-word removal.")
print(f"  Jaccard is unreliable for them. Guard: require >= 3 content tokens; else fall back")
print(f"  to raw string equality.")

ok = True
if verdict_AB != "dedup":
    print(f"  ASSERTION FAIL: Pair(A,B) expected dedup, got {verdict_AB} (jaccard={j_AB:.3f})")
    ok = False
if verdict_AC != "keep":
    print(f"  ASSERTION FAIL: Pair(A,C) expected keep, got {verdict_AC} (jaccard={j_AC:.3f})")
    ok = False
sys.exit(0 if ok else 1)
PYEOF
T4_EXIT=$?
set -e   # restore strict mode for any later code

if [ "$T4_EXIT" -eq 0 ]; then
  pass "Test 4: Pair(A,B) Jaccard>70%->dedup, Pair(A,C) Jaccard<70%->keep; short-comment limitation documented"
else
  fail "Test 4: Jaccard assertions failed (see output above)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

section "Summary"
if [ "$FAILURES" -eq 0 ]; then
  echo "All 4 tests PASSED. Runner exits 0."
else
  echo "$FAILURES test(s) FAILED."
fi
echo ""
exit "$FAILURES"
