#!/bin/bash
# tests/g4-atomic-write/test.sh — smoke test for G4 atomic questionnaire write.
#
# Asserts:
#   1. Happy path: after a successful atomic write, QFILE exists with expected
#      content and no .tmp file is left behind.
#   2. Error path: if the write block raises before os.rename, QFILE is absent
#      and the .tmp file is cleaned up.
#
# Dependencies: python3 (already required by the production script).

set -euo pipefail

PASS=0
FAIL=0

ok()   { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

count_tmp() {
  # Count *.tmp files safely — returns 0 even when glob matches nothing.
  python3 -c "
import os, sys
d = sys.argv[1]
n = sum(1 for f in os.listdir(d) if f.endswith('.tmp'))
print(n)
" "$1"
}

# ---------------------------------------------------------------------------
# Test 1 — happy path: file written atomically, no .tmp left behind.
# ---------------------------------------------------------------------------
echo "[G4-atomic-write] Test 1: happy path"

QFILE="$TMPDIR_TEST/test-questionnaire.yaml"
CONTENT="scope: hello-world"

python3 - "$QFILE" "$CONTENT" <<'PYEOF'
import os, tempfile, sys

qfile = sys.argv[1]
out   = sys.argv[2]
qdir  = os.path.dirname(os.path.abspath(qfile))

fd, tmp = tempfile.mkstemp(dir=qdir, suffix=".tmp")
os.fchmod(fd, 0o644)   # restore default umask permissions
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(out)
        fh.flush()
        os.fsync(fh.fileno())
    os.rename(tmp, qfile)
    dfd = os.open(qdir, os.O_RDONLY)
    try:
        os.fsync(dfd)
    finally:
        os.close(dfd)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PYEOF

# Assert: QFILE exists
if [[ -f "$QFILE" ]]; then
  ok "QFILE exists after atomic write"
else
  fail "QFILE missing after atomic write"
fi

# Assert: content is correct
ACTUAL=$(python3 -c "import sys; print(open(sys.argv[1]).read(), end='')" "$QFILE")
if [[ "$ACTUAL" == "$CONTENT" ]]; then
  ok "QFILE content matches expected"
else
  fail "QFILE content mismatch: expected '$CONTENT', got '$ACTUAL'"
fi

# Assert: no .tmp file left behind
TMP_COUNT=$(count_tmp "$TMPDIR_TEST")
if [[ "$TMP_COUNT" -eq 0 ]]; then
  ok "no .tmp file left behind on success"
else
  fail ".tmp file still present after successful write (count=$TMP_COUNT)"
fi

# Assert: file permissions are 644
PERM=$(stat -c '%a' "$QFILE")
if [[ "$PERM" == "644" ]]; then
  ok "QFILE permissions are 644"
else
  fail "QFILE permissions expected 644, got $PERM"
fi

# ---------------------------------------------------------------------------
# Test 2 — error path: exception before rename → QFILE absent, .tmp cleaned.
# ---------------------------------------------------------------------------
echo "[G4-atomic-write] Test 2: error path (exception before rename)"

QFILE2="$TMPDIR_TEST/test-questionnaire2.yaml"

python3 - "$QFILE2" <<'PYEOF2' || true
import os, tempfile, sys

qfile = sys.argv[1]
out   = "scope: should-not-appear"
qdir  = os.path.dirname(os.path.abspath(qfile))

fd, tmp = tempfile.mkstemp(dir=qdir, suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(out)
        fh.flush()
        os.fsync(fh.fileno())
    raise RuntimeError("simulated error before rename")
    os.rename(tmp, qfile)  # never reached
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PYEOF2

# Assert: QFILE2 absent (rename never happened)
if [[ ! -f "$QFILE2" ]]; then
  ok "QFILE absent after exception before rename"
else
  fail "QFILE present — should be absent when rename was skipped"
fi

# Assert: .tmp cleaned up by except block
TMP_COUNT2=$(count_tmp "$TMPDIR_TEST")
if [[ "$TMP_COUNT2" -eq 0 ]]; then
  ok ".tmp cleaned up in error path"
else
  fail ".tmp still present after error path (count=$TMP_COUNT2)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
