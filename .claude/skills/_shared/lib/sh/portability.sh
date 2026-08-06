#!/usr/bin/env bash
# portability.sh — Portable GNU-ism shims (realpath, flock, etc.)
# Sourced, not executed directly.
# Provides fallbacks for GNU tools missing on BSD/macOS.

[[ -n "${_PORTABILITY_SH_LOADED:-}" ]] && return 0
_PORTABILITY_SH_LOADED=1

# portable_realpath — portable 'realpath -e' (resolve and verify existence)
# Usage: portable_realpath <path>
# Returns: absolute, normalized path
# Exits 1 if path does not exist (matching GNU realpath -e behavior)
# Tries: realpath -e (GNU) → grealpath -e (GNU coreutils on macOS) → python3 fallback
portable_realpath() {
    local path="${1:?portable_realpath: path argument required}"

    # Try GNU realpath -e first
    if realpath -e "$path" 2>/dev/null; then
        return 0
    fi

    # Try grealpath -e (Homebrew GNU coreutils on macOS)
    if command -v grealpath >/dev/null 2>&1; then
        if grealpath -e "$path" 2>/dev/null; then
            return 0
        fi
    fi

    # Fall back to python3 (portable, widely available)
    # realpath canonicalizes path; we check existence separately to match realpath -e
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys; p=sys.argv[1]; rp=os.path.realpath(p); (os.path.exists(rp) or sys.exit(1)); print(rp)' "$path"
        return $?
    fi

    # No suitable tool found
    echo "[ERROR] portable_realpath: no realpath implementation available" >&2
    echo "  tried: realpath -e, grealpath -e, python3" >&2
    return 1
}

# portable_lock — acquire exclusive lock on file descriptor
# Usage: portable_lock <fd> <lockfile>
# Returns: 0 = lock acquired, 2 = lock held (contention), 1 = system unavailable
# Tries: flock(1) → python3 fcntl fallback
# Caller must open fd (e.g., exec 202>"$lockfile"; portable_lock 202 "$lockfile")
portable_lock() {
    local fd="${1:?portable_lock: fd argument required}"
    local lockfile="${2:?portable_lock: lockfile argument required}"

    # Try GNU flock first (Linux, BSD with flock port)
    if command -v flock >/dev/null 2>&1; then
        flock -n "$fd" 2>/dev/null && return 0
        # flock failed: distinguish contention (rc=1) from system errors (rc=other → 1)
        local flock_rc=$?
        if [[ $flock_rc -eq 1 ]]; then
            return 2  # Lock held (contention)
        else
            return 1  # Other error (fd invalid, permission, etc.)
        fi
    fi

    # Fall back to python3 fcntl (POSIX-portable)
    if command -v python3 >/dev/null 2>&1; then
        python3 -c '
import fcntl
import sys
try:
    fd = int(sys.argv[1])
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    sys.exit(0)
except BlockingIOError:
    sys.exit(2)
except (ValueError, OSError) as e:
    print(f"[ERROR] portable_lock: {e}", file=sys.stderr)
    sys.exit(1)
' "$fd"
        return $?
    fi

    # No suitable tool found
    echo "[ERROR] portable_lock ($lockfile): no lock implementation available (flock/fcntl)" >&2
    return 1
}

# portable_realpath_m — portable 'realpath -m' (resolve without requiring existence)
# Usage: portable_realpath_m <path>
# Returns: absolute, normalized path
# Does NOT exit 1 if path does not exist (differs from portable_realpath)
# Tries: realpath -m (GNU) → python3 fallback
portable_realpath_m() {
    local path="${1:?portable_realpath_m: path argument required}"

    # Try GNU realpath -m first
    if realpath -m "$path" 2>/dev/null; then
        return 0
    fi

    # Try grealpath -m (Homebrew GNU coreutils on macOS)
    if command -v grealpath >/dev/null 2>&1; then
        if grealpath -m "$path" 2>/dev/null; then
            return 0
        fi
    fi

    # Fall back to python3 os.path.realpath (normalizes without requiring existence)
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path"
        return $?
    fi

    # No suitable tool found
    echo "[ERROR] portable_realpath_m: no realpath implementation available" >&2
    echo "  tried: realpath -m, grealpath -m, python3" >&2
    return 1
}
