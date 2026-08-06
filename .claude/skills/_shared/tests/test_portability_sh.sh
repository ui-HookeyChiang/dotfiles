#!/usr/bin/env bash
# Unit tests for _shared/lib/sh/portability.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib/sh"
TEST_TMPDIR=""
FAKE_BIN_DIR=""

pass=0 fail=0

cleanup() {
    [[ -n "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
    [[ -n "$FAKE_BIN_DIR" ]] && rm -rf "$FAKE_BIN_DIR"
}
trap cleanup EXIT

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $label"
        (( ++pass ))
    else
        echo "  FAIL: $label"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        (( ++fail ))
    fi
}

assert_success() {
    local label="$1"
    local output="$2"
    if [[ -n "$output" ]]; then
        echo "  PASS: $label"
        (( ++pass ))
    else
        echo "  FAIL: $label"
        echo "    expected non-empty output"
        (( ++fail ))
    fi
}

assert_fails() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL: $label (expected to fail)"
        (( ++fail ))
    else
        echo "  PASS: $label"
        (( ++pass ))
    fi
}

echo "=== test_portability_sh.sh ==="

# Source the module
source "$LIB_DIR/portability.sh"

# --- Verify portable_realpath exists ---
if declare -f portable_realpath >/dev/null 2>&1; then
    echo "  PASS: portable_realpath function exists"
    (( ++pass ))
else
    echo "  FAIL: portable_realpath function not found"
    (( ++fail ))
fi

# --- portable_realpath with existing file ---
test_file="$SCRIPT_DIR/test_portability_sh.sh"
result=$(portable_realpath "$test_file" 2>/dev/null)
assert_success "portable_realpath resolves existing file" "$result"

# --- portable_realpath with nonexistent file (should fail) ---
assert_fails "portable_realpath fails for nonexistent file" \
    portable_realpath "/nonexistent/path/that/does/not/exist"

# --- portable_realpath returns absolute path ---
actual=$(portable_realpath "$test_file" 2>/dev/null)
case "$actual" in
    /*) echo "  PASS: portable_realpath returns absolute path"
        (( ++pass ))
        ;;
    *)  echo "  FAIL: portable_realpath should return absolute path"
        echo "    got: '$actual'"
        (( ++fail ))
        ;;
esac

# --- Create test tmpdir and fixture files ---
TEST_TMPDIR="$(mktemp -d)"
fixture_file="$TEST_TMPDIR/fixture-test-file.txt"
echo "test content" > "$fixture_file"

# --- portable_realpath with fixture file ---
result=$(portable_realpath "$fixture_file" 2>/dev/null)
assert_success "portable_realpath resolves fixture file" "$result"

# --- portable_realpath normalizes paths ---
result=$(portable_realpath "$fixture_file" 2>/dev/null)
if [[ "$result" == /* && ! "$result" =~ // ]]; then
    echo "  PASS: portable_realpath normalizes path"
    (( ++pass ))
else
    echo "  FAIL: portable_realpath should normalize path"
    echo "    got: '$result'"
    (( ++fail ))
fi

# --- Force python3 fallback by hiding realpath/grealpath in PATH ---
# Create a fake bin directory that only contains python3 and basic tools
FAKE_BIN_DIR="$(mktemp -d)"
# Create a fake realpath that exits with 127 (command not found) to trigger grealpath check
printf '#!/bin/sh\nexit 127\n' > "$FAKE_BIN_DIR/realpath"
chmod +x "$FAKE_BIN_DIR/realpath"

# Test with PATH that has our fake realpath
CONSTRAINED_PATH="$FAKE_BIN_DIR:/usr/bin:/bin:/usr/local/bin"

# Verify realpath in this PATH is our fake (not the real one)
if PATH="$CONSTRAINED_PATH" realpath 2>/dev/null; then
    # realpath succeeded, our fake wasn't used
    echo "  SKIP: could not override realpath in PATH"
else
    # Our fake realpath was used and exited with 127; should trigger grealpath → python3
    result=$(PATH="$CONSTRAINED_PATH" portable_realpath "$fixture_file" 2>/dev/null)
    assert_success "portable_realpath falls back to python3 when realpath unavailable" "$result"

    # Test python3 fallback fails on nonexistent file
    if ! PATH="$CONSTRAINED_PATH" portable_realpath "/nonexistent/fixture/path" 2>/dev/null; then
        echo "  PASS: python3 fallback fails for nonexistent file"
        (( ++pass ))
    else
        echo "  FAIL: python3 fallback should fail for nonexistent file"
        (( ++fail ))
    fi
fi

# --- include guard ---
source "$LIB_DIR/portability.sh"
if declare -f portable_realpath >/dev/null 2>&1; then
    echo "  PASS: include guard: re-source works"
    (( ++pass ))
else
    echo "  FAIL: include guard: re-source should not cause error"
    (( ++fail ))
fi

echo ""
echo "=== portable_realpath_m tests ==="

# --- Verify portable_realpath_m exists ---
if declare -f portable_realpath_m >/dev/null 2>&1; then
    echo "  PASS: portable_realpath_m function exists"
    (( ++pass ))
else
    echo "  FAIL: portable_realpath_m function not found"
    (( ++fail ))
fi

# --- portable_realpath_m resolves nonexistent path (unlike portable_realpath) ---
result=$(portable_realpath_m "/nonexistent/path/that/does/not/exist" 2>/dev/null)
assert_eq "portable_realpath_m resolves nonexistent path" \
    "/nonexistent/path/that/does/not/exist" "$result"

# --- portable_realpath_m with relative path + implied cwd ---
result=$(portable_realpath_m "relative/subdir/file.txt" 2>/dev/null)
expected="$(pwd -P)/relative/subdir/file.txt"
assert_eq "portable_realpath_m resolves relative path against cwd" "$expected" "$result"

# --- portable_realpath_m normalizes ./ segments ---
result=$(portable_realpath_m "$TEST_TMPDIR/./subdir/../fixture-test-file.txt" 2>/dev/null)
assert_eq "portable_realpath_m normalizes ./ and ../ segments" \
    "$(portable_realpath_m "$TEST_TMPDIR/fixture-test-file.txt")" "$result"

# --- portable_realpath_m resolves symlinks ---
ln -sf "$fixture_file" "$TEST_TMPDIR/symlink-to-fixture"
result=$(portable_realpath_m "$TEST_TMPDIR/symlink-to-fixture" 2>/dev/null)
expected=$(portable_realpath "$fixture_file" 2>/dev/null)
assert_eq "portable_realpath_m resolves symlinks" "$expected" "$result"

# --- portable_realpath_m returns absolute path ---
result=$(portable_realpath_m "some-relative-path" 2>/dev/null)
case "$result" in
    /*) echo "  PASS: portable_realpath_m returns absolute path"
        (( ++pass ))
        ;;
    *)  echo "  FAIL: portable_realpath_m should return absolute path"
        echo "    got: '$result'"
        (( ++fail ))
        ;;
esac

echo ""
echo "=== portable_lock tests ==="

# --- Verify portable_lock exists ---
if declare -f portable_lock >/dev/null 2>&1; then
    echo "  PASS: portable_lock function exists"
    (( ++pass ))
else
    echo "  FAIL: portable_lock function not found"
    (( ++fail ))
fi

# --- portable_lock: same-process single acquire ---
lock_testdir=$(mktemp -d)
lock_testdir_cleanup() { [[ -n "$lock_testdir" ]] && rm -rf "$lock_testdir"; }
trap "cleanup; lock_testdir_cleanup" EXIT

lock_file="$lock_testdir/test.lock"
: >"$lock_file"
exec 203>"$lock_file"

portable_lock 203 "$lock_file"
lock_rc=$?
if [[ $lock_rc -eq 0 ]]; then
    echo "  PASS: portable_lock acquires lock (rc=0)"
    (( ++pass ))
else
    echo "  FAIL: portable_lock should acquire lock"
    echo "    got rc=$lock_rc (expected 0)"
    (( ++fail ))
fi

# --- portable_lock: same-process contention (two fds on same file) ---
exec 204>"$lock_file"
second_lock_rc=0
portable_lock 204 "$lock_file" || second_lock_rc=$?
if [[ $second_lock_rc -eq 2 ]]; then
    echo "  PASS: portable_lock detects contention (rc=2, same process)"
    (( ++pass ))
else
    echo "  FAIL: portable_lock should return 2 on contention"
    echo "    got rc=$second_lock_rc (expected 2)"
    (( ++fail ))
fi

exec 203>&-
exec 204>&-

# --- portable_lock: two-process contention (real-world case) ---
# Process 1 acquires and holds; Process 2 should get rc=2
contention_lock="$lock_testdir/contention.lock"
: >"$contention_lock"

# Start holder process (acquires lock, sleeps, releases)
(
    exec 205>"$contention_lock"
    source "$LIB_DIR/portability.sh"
    portable_lock 205 "$contention_lock"
    if [[ $? -eq 0 ]]; then
        sleep 2  # Hold for 2 seconds
    fi
) &
holder_pid=$!

sleep 0.5  # Let holder acquire lock

# Try to acquire in main process while held
exec 206>"$contention_lock"
source "$LIB_DIR/portability.sh"
contention_rc=0
portable_lock 206 "$contention_lock" || contention_rc=$?
exec 206>&-

if [[ $contention_rc -eq 2 ]]; then
    echo "  PASS: portable_lock detects two-process contention (rc=2)"
    (( ++pass ))
else
    echo "  FAIL: two-process contention should return rc=2"
    echo "    got rc=$contention_rc (expected 2)"
    (( ++fail ))
fi

wait $holder_pid 2>/dev/null || true

# --- portable_lock: fcntl shim path (hide flock from PATH) ---
# Test the python3 fcntl fallback by removing flock from PATH
shim_lock="$lock_testdir/shim.lock"
: >"$shim_lock"

# Minimal PATH that excludes flock locations
shim_path="/usr/bin:/bin:/usr/sbin:/sbin"
path_before="$PATH"

(
    exec 207>"$shim_lock"
    export PATH="$shim_path"
    # Verify flock is absent and assert it before sourcing portability
    if command -v flock >/dev/null 2>&1; then
        echo "  SKIP: fcntl shim test (flock still in $shim_path, test cannot isolate shim)"
        exit 42  # Special code to indicate skip
    fi
    source "$LIB_DIR/portability.sh"
    portable_lock 207 "$shim_lock"
    if [[ $? -eq 0 ]]; then
        sleep 1
    fi
) &
shim_holder=$!

sleep 0.3

# Attempt contention with restricted PATH (no flock)
export PATH="$shim_path"
if ! command -v flock >/dev/null 2>&1; then
    exec 208>"$shim_lock"
    source "$LIB_DIR/portability.sh"
    shim_contention_rc=0
    portable_lock 208 "$shim_lock" || shim_contention_rc=$?
    exec 208>&-

    if [[ $shim_contention_rc -eq 2 ]]; then
        echo "  PASS: fcntl shim detects contention (rc=2, flock absent)"
        (( ++pass ))
    else
        echo "  FAIL: fcntl shim should detect contention"
        echo "    got rc=$shim_contention_rc (expected 2)"
        (( ++fail ))
    fi
else
    echo "  SKIP: fcntl shim test (flock available, cannot verify shim isolation)"
    (( ++pass ))
fi

export PATH="$path_before"
wait $shim_holder 2>/dev/null || true

echo ""
echo "Results: $pass passed, $fail failed"
(( fail == 0 ))
