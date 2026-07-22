#!/bin/bash
# tests/resolve-skill-creator/test.sh
# Verify resolve-skill-creator.sh — the 4-layer $SC_ROOT resolver.
#
# These ACs exercise the deterministic, install-independent paths: the
# $SKILL_CREATOR_DIR override (layer 1) and the validation gate (layer 4).
# They do NOT depend on a real plugin install (layers 2/3 are environment-
# specific), so the suite passes hermetically in CI.
#
#   AC1 override-valid: $SKILL_CREATOR_DIR pointing at a fixture with
#       scripts/__init__.py + scripts/run_eval.py echoes that path, exit 0.
#   AC2 override-invalid + nothing else resolvable: a bogus $SKILL_CREATOR_DIR
#       (under an empty plugins HOME) falls through to exit 2.
#   AC3 validation gate: a fixture missing run_eval.py is rejected (exit 2).
#   AC4 init-marker is existence-only: a 0-byte __init__.py still validates.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_WRITER="$(cd "$HERE/../../.." && pwd)"
SCRIPT="$SKILL_WRITER/scripts/resolve-skill-creator.sh"

PASSED=0
FAILED=0
pass () { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail () { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

# make_fixture <root> [--no-run-eval]: build a fake $SC_ROOT.
make_fixture () {
  local root="$1"; shift || true
  mkdir -p "$root/scripts"
  : > "$root/scripts/__init__.py"   # 0-byte package marker
  if [[ "${1:-}" != "--no-run-eval" ]]; then
    echo "# stub" > "$root/scripts/run_eval.py"
  fi
}

# --- AC1: valid override echoes the path, exit 0 ----------------------------
ac1 () {
  local fx out rc
  fx="$(mktemp -d)"
  make_fixture "$fx"
  out="$(SKILL_CREATOR_DIR="$fx" bash "$SCRIPT" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$out" == "$fx" ]]; then
    pass "AC1 valid \$SKILL_CREATOR_DIR override echoes path + exit 0"
  else
    fail "AC1 expected exit 0 + path '$fx', got rc=$rc out='$out'"
  fi
  rm -rf "$fx"
}

# --- AC2: invalid override + empty plugins HOME -> exit 2 -------------------
ac2 () {
  local fakehome rc
  fakehome="$(mktemp -d)"        # empty: no installed_plugins.json, no cache
  HOME="$fakehome" SKILL_CREATOR_DIR="$fakehome/does-not-exist" \
    bash "$SCRIPT" >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 2 ]]; then
    pass "AC2 invalid override + no install -> exit 2"
  else
    fail "AC2 expected exit 2, got rc=$rc"
  fi
  rm -rf "$fakehome"
}

# --- AC3: fixture missing run_eval.py is rejected --------------------------
ac3 () {
  local fx fakehome rc
  fx="$(mktemp -d)"
  fakehome="$(mktemp -d)"
  make_fixture "$fx" --no-run-eval
  HOME="$fakehome" SKILL_CREATOR_DIR="$fx" bash "$SCRIPT" >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 2 ]]; then
    pass "AC3 missing scripts/run_eval.py -> rejected (exit 2)"
  else
    fail "AC3 expected exit 2 for fixture without run_eval.py, got rc=$rc"
  fi
  rm -rf "$fx" "$fakehome"
}

# --- AC4: 0-byte __init__.py still validates (existence, not non-empty) -----
ac4 () {
  local fx out rc
  fx="$(mktemp -d)"
  make_fixture "$fx"            # __init__.py is 0 bytes
  [[ -s "$fx/scripts/__init__.py" ]] && { fail "AC4 setup error: __init__.py not empty"; rm -rf "$fx"; return; }
  out="$(SKILL_CREATOR_DIR="$fx" bash "$SCRIPT" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$out" == "$fx" ]]; then
    pass "AC4 0-byte __init__.py validates (existence-only marker)"
  else
    fail "AC4 expected exit 0 with 0-byte init, got rc=$rc out='$out'"
  fi
  rm -rf "$fx"
}

ac1; ac2; ac3; ac4

echo
echo "resolve-skill-creator resolver: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
