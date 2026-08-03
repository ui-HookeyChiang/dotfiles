#!/usr/bin/env bash
# Tests for flow-dev/scripts/parse-blocked-by.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../parse-blocked-by.sh"

PASSED=0
FAILED=0
pass() { ((PASSED++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); echo "  FAIL: $1" >&2; }

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# --- Case 1: "None." single word ---
echo "Case 1: None."
cat > "$TMPDIR_ROOT/t1.md" <<'EOF'
## Blocked by

None.

## Other
EOF
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/t1.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ "$out" == "[]" ]]; then
  pass "None. → empty array"
else
  fail "None.: rc=$rc out=$out"
fi

# --- Case 2: "None — can start immediately" ---
echo "Case 2: None — long form"
cat > "$TMPDIR_ROOT/t2.md" <<'EOF'
## Blocked by

None — can start immediately (independent of T0 landing).
EOF
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/t2.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ "$out" == "[]" ]]; then
  pass "None long form → empty array"
else
  fail "None long form: rc=$rc out=$out"
fi

# --- Case 3: backtick-wrapped path ---
echo "Case 3: backtick path"
cat > "$TMPDIR_ROOT/t3.md" <<'EOF'
## Blocked by

`docs/ticket/2026-06-30-rename-adversarial-review.md`
EOF
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/t3.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ "$out" == '["docs/ticket/2026-06-30-rename-adversarial-review.md"]' ]]; then
  pass "backtick path parsed"
else
  fail "backtick path: rc=$rc out=$out"
fi

# --- Case 4: list item with reason ---
echo "Case 4: list item with parenthetical"
cat > "$TMPDIR_ROOT/t4.md" <<'EOF'
## Blocked by

- docs/ticket/2026-06-26-skill-guidelines-delegate-reasoning-rule.md (the rule must exist before the auditor checks for it)
EOF
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/t4.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ "$out" == '["docs/ticket/2026-06-26-skill-guidelines-delegate-reasoning-rule.md"]' ]]; then
  pass "list item with reason parsed"
else
  fail "list item: rc=$rc out=$out"
fi

# --- Case 5: multiple blockers ---
echo "Case 5: multiple blockers"
cat > "$TMPDIR_ROOT/t5.md" <<'EOF'
## Blocked by

- docs/ticket/2026-07-01-first.md (reason A)
- docs/ticket/2026-07-02-second.md (reason B)
EOF
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/t5.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ "$out" == '["docs/ticket/2026-07-01-first.md","docs/ticket/2026-07-02-second.md"]' ]]; then
  pass "multiple blockers parsed"
else
  fail "multiple blockers: rc=$rc out=$out"
fi

# --- Case 6: missing file ---
echo "Case 6: missing file"
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/nonexistent.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'STOP-SAFE'; then
  pass "missing file STOP-SAFE"
else
  fail "missing file: rc=$rc out=$out"
fi

# --- Case 7: no Blocked by section ---
echo "Case 7: no section"
cat > "$TMPDIR_ROOT/t7.md" <<'EOF'
## Problem

Something is wrong.
EOF
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/t7.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'STOP-SAFE'; then
  pass "no section STOP-SAFE"
else
  fail "no section: rc=$rc out=$out"
fi

# --- Case 8: unparseable line ---
echo "Case 8: unparseable line"
cat > "$TMPDIR_ROOT/t8.md" <<'EOF'
## Blocked by

- something that is not a ticket path at all
EOF
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/t8.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'STOP-SAFE.*Unparseable'; then
  pass "unparseable line STOP-SAFE"
else
  fail "unparseable: rc=$rc out=$out"
fi

# --- Case 9: empty section (no content lines) ---
echo "Case 9: empty section"
cat > "$TMPDIR_ROOT/t9.md" <<'EOF'
## Blocked by

## Next
EOF
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/t9.md" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ "$out" == "[]" ]]; then
  pass "empty section → empty array"
else
  fail "empty section: rc=$rc out=$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
