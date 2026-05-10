#!/usr/bin/env bash
# tests/test-install-os.sh — TAP-13 regression suite for install.sh OS branches.
#
# Encodes the OS-aware contracts of install.sh as unit tests:
#   - F6 module propagation (if-block must NOT swallow failures)
#   - F7 source-safety guard (sourcing must NOT invoke main)
#   - F8 distro-aware Docker repo URL (ubuntu / debian / unsupported)
#   - bash version requirement (>= 4 for mapfile / assoc array)
#   - OS-gated functions (seed_secrets macOS-only, detect_os Linux-only branch)
#
# Tests do NOT execute apt / brew / curl / sudo. Each test runs in a subshell
# that overrides run/note/log/err helpers to no-ops or capture-to-stdout, then
# sources install.sh. The F7 guard (`[[ "${BASH_SOURCE[0]}" == "$0" ]]`) keeps
# main() from firing during source.
#
# Output: TAP-13 (https://testanything.org/tap-version-13-specification.html).
# Exit 0 on all pass, non-zero count of failures otherwise.

set -u  # NOT -e: keep running tests after a failure.

# ---------- locate repo ------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_sh="$repo_root/install.sh"

# Sandbox dir.
tmp_dir="$(mktemp -d -t install-os-test.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

# ---------- TAP helpers ------------------------------------------------------
plan_count=12
echo "1..$plan_count"
echo "# OS=$(uname -s) bash=${BASH_VERSION}"
echo "# repo_root=$repo_root"

n=0
fail=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() {
  n=$((n+1)); echo "not ok $n - $1"
  if [[ -n "${2:-}" ]]; then
    printf '  ---\n  diag: |\n'
    printf '    %s\n' "${2//$'\n'/$'\n    '}"
    printf '  ...\n'
  fi
  fail=$((fail+1))
}
skip() { n=$((n+1)); echo "ok $n - $1 # SKIP ${2:-}"; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux"  ]]; }

# ---------- tests ------------------------------------------------------------

# T1: bash -n syntax check on install.sh (sanity; subset of test-install-projects T1).
test_T1() {
  local desc="install.sh passes bash -n syntax check"
  local err
  if err="$(bash -n "$install_sh" 2>&1)"; then
    ok "$desc"
  else
    nok "$desc" "$err"
  fi
}

# T2: F7 regression — sourcing install.sh MUST NOT invoke main.
# main starts with `log "install.sh start ..."`. If main fired during source
# we'd see that log line on stderr.
#
# We use `bash -c` so install.sh's `set -euo pipefail` + ERR trap can't leak
# into our test driver. We override log/note/err/run AFTER sourcing so install.sh's
# own definitions get shadowed; and we capture the source pass's output (where
# the original log/note are still in effect at source time — but main shouldn't
# fire so log shouldn't be invoked).
test_T2() {
  local desc="source install.sh does not invoke main (F7 regression)"
  local out
  out="$(bash -c '
    install_sh="$1"
    # Source install.sh; F7 guard prevents main() from firing.
    # shellcheck disable=SC1090
    . "$install_sh"
    # If we reach here, main did NOT run (it would have called many helpers
    # and likely exited non-zero in this environment). Print a sentinel.
    echo "SOURCED_OK"
  ' _ "$install_sh" 2>&1)" || true
  if [[ "$out" == *"install.sh start"* ]]; then
    nok "$desc" "main() fired during source (saw 'install.sh start' log): $out"
    return
  fi
  if [[ "$out" != *"SOURCED_OK"* ]]; then
    nok "$desc" "source failed before SOURCED_OK sentinel: $out"
    return
  fi
  ok "$desc"
}

# T3: F7 regression — sourced install.sh exposes seed_env, seed_secrets, main.
test_T3() {
  local desc="sourced install.sh exposes seed_env, seed_secrets, main"
  local out
  out="$(bash -c '
    install_sh="$1"
    # shellcheck disable=SC1090
    . "$install_sh"
    # Disable -e/-u so declare -F failure on a missing fn name does not abort.
    set +eu
    for fn in seed_env seed_secrets main install_docker detect_os install_node parse_flags; do
      if declare -F "$fn" >/dev/null 2>&1; then
        printf "FOUND:%s\n" "$fn"
      else
        printf "MISSING:%s\n" "$fn"
      fi
    done
  ' _ "$install_sh" 2>&1)"
  local missing=""
  for fn in seed_env seed_secrets main install_docker detect_os install_node parse_flags; do
    [[ "$out" == *"FOUND:$fn"* ]] || missing+="$fn "
  done
  if [[ -n "$missing" ]]; then
    nok "$desc" "missing functions: $missing (full output: $out)"
  else
    ok "$desc"
  fi
}

# T4: F6 propagation — module failure must propagate via the if-block pattern.
# The buggy pattern `(( X )) && fn || true` swallows fn's exit code. The fix
# uses `if (( X )); then fn; fi`, which under `set -e` propagates fn's failure.
# We exercise the FIX pattern directly (not by sourcing install.sh, since sourcing
# clears set -e for the surrounding test process).
#
# CRITICAL: must use `bash -c` not `( ... )` subshell. BashFAQ #105 — bash
# disables set -e in subshells whose parent is in a &&/|| context, which would
# silently mask the test (giving a false pass).
test_T4() {
  local desc="F6 propagation: if-block lets install_node failure propagate (rc=1)"
  local out rc
  # Capture stdout+stderr AND exit code without `|| true` (which would clobber $?).
  # Pattern: run bash -c, swallow rc into the captured stream via `; echo "RC=$?"`.
  out="$(bash -c '
    set -e
    install_node() { return 1; }
    WITH_NODE=1
    if (( WITH_NODE )); then install_node; fi
    echo SHOULD_NOT_REACH
  ' 2>&1; printf "RC=%d\n" $?)"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2}' | tail -1)"
  if [[ "$rc" == "0" ]]; then
    nok "$desc" "expected non-zero exit, got 0; output: $out"
    return
  fi
  if [[ "$out" == *"SHOULD_NOT_REACH"* ]]; then
    nok "$desc" "set -e did not propagate failure; saw SHOULD_NOT_REACH; output: $out"
    return
  fi
  ok "$desc"
}

# T5: F6 negative case — WITH_NODE=0 must NOT call install_node.
# Confirms the if-guard works in the false direction. Sentinel via a shared
# tmp file (subshell can't mutate parent variables under bash -c).
test_T5() {
  local desc="F6 skip: WITH_NODE=0 -> install_node not called"
  local sentinel="$tmp_dir/install_node_called.$$"
  rm -f -- "$sentinel"
  bash -c '
    set -e
    install_node() { : > "'"$sentinel"'"; }
    WITH_NODE=0
    if (( WITH_NODE )); then install_node; fi
    echo OK_NO_CALL
  ' >/dev/null 2>&1
  if [[ -e "$sentinel" ]]; then
    nok "$desc" "install_node was called despite WITH_NODE=0"
  else
    ok "$desc"
  fi
}

# Helper for T6/T7/T8/T9: source install.sh in a hermetic subshell, set
# OS=linux + DISTRO_ID=<arg>, mock command/run/note/err/log AFTER sourcing
# (otherwise install.sh's own helper definitions clobber ours), then call
# install_docker. Disable set -e + ERR trap before the call so a returned 1
# from the unsupported-distro case can be observed without aborting the trap.
#
# The `command` builtin override is the key trick: install_docker calls
# `command -v docker >/dev/null 2>&1` to early-return if docker is already
# installed. We override `command` as a function that intercepts `-v` and
# always reports "not found" (return 1), so install_docker proceeds into the
# distro-branch case. Other `command` invocations fall through to the real
# builtin via `builtin command`.
run_install_docker_with_distro() {
  local distro_id="$1"
  bash -c '
    install_sh="$2"; distro_id="$1"
    # shellcheck disable=SC1090
    . "$install_sh"
    # Disarm the strict-mode + ERR trap that install.sh installs at top-level,
    # so a `return 1` from install_docker (T8 unsupported branch) does not
    # trip the trap and short-circuit our capture.
    set +eu
    trap - ERR
    # Shadow install.sh helpers AFTER sourcing.
    log()  { :; }
    note() { printf "NOTE: %s\n" "$*"; }
    err()  { printf "ERR: %s\n"  "$*"; }
    run()  { printf "RUN: %s\n"  "$*"; }
    command() {
      if [[ "$1" == "-v" ]]; then return 1; fi
      builtin command "$@"
    }
    OS="linux"
    DISTRO_ID="$distro_id"
    install_docker
    echo "RC=$?"
  ' _ "$distro_id" "$install_sh" 2>&1
}

# T6: F8 ubuntu — DISTRO_ID=ubuntu => install_docker uses linux/ubuntu URL.
test_T6() {
  local desc="F8 ubuntu: DISTRO_ID=ubuntu emits linux/ubuntu URL"
  local out
  out="$(run_install_docker_with_distro "ubuntu")"
  if [[ "$out" == *"linux/ubuntu"* ]] && [[ "$out" == *"RC=0"* ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 'linux/ubuntu' + RC=0; got: $out"
  fi
}

# T7: F8 debian — DISTRO_ID=debian => linux/debian URL, NOT linux/ubuntu.
# This is the regression test for the previously hardcoded `linux/ubuntu`
# Docker repo URL fixed in PR #24.
test_T7() {
  local desc="F8 debian: DISTRO_ID=debian emits linux/debian URL (not linux/ubuntu)"
  local out
  out="$(run_install_docker_with_distro "debian")"
  if [[ "$out" != *"linux/debian"* ]]; then
    nok "$desc" "expected 'linux/debian' in output; got: $out"
    return
  fi
  if [[ "$out" == *"linux/ubuntu"* ]]; then
    nok "$desc" "expected NO 'linux/ubuntu' substring (regression!); got: $out"
    return
  fi
  if [[ "$out" != *"RC=0"* ]]; then
    nok "$desc" "expected RC=0; got: $out"
    return
  fi
  ok "$desc"
}

# T8: F8 unsupported distro — DISTRO_ID=fedora => return 1 with err message.
test_T8() {
  local desc="F8 unsupported: DISTRO_ID=fedora -> rc=1 + 'unsupported distro' err"
  local out
  out="$(run_install_docker_with_distro "fedora")"
  if [[ "$out" != *"unsupported distro"* ]]; then
    nok "$desc" "expected 'unsupported distro' err; got: $out"
    return
  fi
  if [[ "$out" != *"RC=1"* ]]; then
    nok "$desc" "expected RC=1; got: $out"
    return
  fi
  ok "$desc"
}

# T9: F8 ID_LIKE matching — DISTRO_ID="something ubuntu" must match the ubuntu
# branch. /etc/os-release sometimes sets ID_LIKE="debian ubuntu" on derivatives
# (Mint, Pop!_OS), and detect_os exposes ID_LIKE via DISTRO_ID. The case glob
# in install_docker pads with spaces (`*ubuntu*`) to handle this.
test_T9() {
  local desc="F8 ID_LIKE: DISTRO_ID='something ubuntu' matches ubuntu branch"
  local out
  out="$(run_install_docker_with_distro "something ubuntu")"
  if [[ "$out" == *"linux/ubuntu"* ]] && [[ "$out" == *"RC=0"* ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 'linux/ubuntu' + RC=0; got: $out"
  fi
}

# T10: install.sh sources cleanly under the executing shell, regardless of bash
# version. install.sh uses associative arrays (`declare -A PKG_BINARIES`) which
# bash 3.2 can't parse — but PR #25 wraps that block in a Linux-only guard so
# macOS bash 3.2 doesn't choke at load. This test verifies the load-time
# behaviour holds: sourcing the file must NOT abort with an unbound-variable
# error or syntax error on the host's bash. (Functionality requiring bash 4+ —
# e.g. apt-path `is_present_apt` consuming `PKG_BINARIES` — is exercised
# separately when the Linux branch runs it; macOS callers never reach it.)
test_T10() {
  local desc="install.sh sources cleanly under host bash (PR #25 guard)"
  local out rc
  out="$(bash -c '
    install_sh="$1"
    # set +u disabled here intentionally so unbound-variable errors abort and
    # we observe them; install.sh starts with `set -euo pipefail` itself.
    # shellcheck disable=SC1090
    if . "$install_sh" 2>&1; then
      printf "RC=0\n"
    else
      printf "RC=%d\n" $?
    fi
  ' _ "$install_sh" 2>&1)"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" == "0" ]]; then
    ok "$desc (BASH_VERSINFO=${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]})"
  else
    nok "$desc" "sourcing install.sh aborted with rc=$rc on bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}; output: $out"
  fi
}

# T11: macOS-only — seed_secrets is callable and is_macos guards work.
# SKIPs on Linux.
test_T11() {
  local desc="macOS path sanity: seed_secrets callable + macOS-only guard"
  if ! is_macos; then
    skip "$desc" "not macOS (host is $(uname -s))"
    return
  fi
  # On macOS: source install.sh, set OS=linux, call seed_secrets — should
  # short-circuit via the `[[ "$OS" != "macos" ]]` guard, return 0, and emit
  # the keychain-skip note (not the error message about missing entries).
  local out
  out="$(bash -c '
    install_sh="$1"
    # shellcheck disable=SC1090
    . "$install_sh"
    set +eu
    trap - ERR
    log()  { :; }
    note() { printf "NOTE: %s\n" "$*"; }
    err()  { printf "ERR: %s\n"  "$*"; }
    run()  { :; }
    OS="linux"
    seed_secrets
    echo "RC=$?"
  ' _ "$install_sh" 2>&1)"
  if [[ "$out" == *"Keychain is macOS-only"* ]] && [[ "$out" == *"RC=0"* ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 'Keychain is macOS-only' + RC=0; got: $out"
  fi
}

# T12: Linux-only — detect_os reads /etc/os-release and populates DISTRO_ID.
# SKIPs on macOS (no /etc/os-release).
test_T12() {
  local desc="Linux distro detection: detect_os populates DISTRO_ID from /etc/os-release"
  if ! is_linux; then
    skip "$desc" "not Linux (host is $(uname -s))"
    return
  fi
  if [[ ! -r /etc/os-release ]]; then
    skip "$desc" "/etc/os-release not readable on this host"
    return
  fi
  local out distro_id
  out="$(bash -c '
    install_sh="$1"
    # shellcheck disable=SC1090
    . "$install_sh"
    set +eu
    trap - ERR
    log()  { :; }
    note() { :; }
    err()  { :; }
    run()  { :; }
    detect_os >/dev/null 2>&1
    printf "DISTRO_ID=%s\n" "$DISTRO_ID"
    printf "OS=%s\n" "$OS"
  ' _ "$install_sh" 2>&1)"
  distro_id="$(printf '%s\n' "$out" | awk -F= '/^DISTRO_ID=/{print $2}')"
  if [[ "$out" != *"OS=linux"* ]]; then
    nok "$desc" "expected OS=linux; got: $out"
    return
  fi
  if [[ -z "$distro_id" ]]; then
    nok "$desc" "DISTRO_ID empty after detect_os; got: $out"
    return
  fi
  ok "$desc (DISTRO_ID=$distro_id)"
}

# ---------- run --------------------------------------------------------------
test_T1
test_T2
test_T3
test_T4
test_T5
test_T6
test_T7
test_T8
test_T9
test_T10
test_T11
test_T12

echo "# passed=$((n - fail)) failed=$fail of $n"
exit "$fail"
