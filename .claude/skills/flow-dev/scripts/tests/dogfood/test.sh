#!/bin/bash
# tests/dogfood/test.sh — TDD for the flow-dev resident dogfood
# (PR4 of the resident-dogfood feature). Asserts:
#
#   AC1: smoke entrypoint (dogfood-smoke.sh) runs the parallel scripts
#        (parallel-layers.sh + merge-train.sh) against a fixture, exits 0,
#        and emits Smoke evidence (run-NNN/smoke/<cmd>.log + <cmd>.exit) —
#        with the exit code CAPTURED (Open Q6), not auto-failing on a
#        deliberately-non-zero command.
#   AC2: behavior preparer (dogfood-prepare.sh) writes a byte-stable
#        behavior/dispatch-prompt.md that carries the HARD sandbox overrides
#        (Open Q3): grep for `feat/dogfood-run-` and `dogfood-run-`.
#        Re-running with the SAME run-id yields a byte-identical prompt.
#   AC3: run-id is never reused — two consecutive preparer runs (auto-detect)
#        allocate run-001 then run-002 (cumulative, monotonic; Open Q4).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../.." && pwd)"
SMOKE="$SCRIPTS/tests/dogfood-smoke.sh"
PREPARE="$SCRIPTS/dogfood-prepare.sh"

PASSED=0
FAILED=0
pass () { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail () { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

# --- AC1: smoke entrypoint emits captured evidence -------------------------
ac1 () {
  local ev rc
  ev="$(mktemp -d)"
  set +e
  bash "$SMOKE" --evidence-dir "$ev" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    fail "AC1 smoke entrypoint should exit 0 (got $rc)"
    rm -rf "$ev"; return
  fi
  # evidence: a run-NNN/smoke/ dir with at least one .log + .exit pair
  local smokedir
  smokedir="$(/bin/ls -d "$ev"/run-*/smoke 2>/dev/null | head -1)"
  if [[ -z "$smokedir" ]]; then
    fail "AC1 expected run-NNN/smoke/ evidence dir under $ev"
    rm -rf "$ev"; return
  fi
  if ! compgen -G "$smokedir/*.log" >/dev/null; then
    fail "AC1 expected at least one smoke/*.log"; rm -rf "$ev"; return
  fi
  if ! compgen -G "$smokedir/*.exit" >/dev/null; then
    fail "AC1 expected at least one smoke/*.exit (Open Q6 exit capture)"; rm -rf "$ev"; return
  fi
  # the .exit file holds a bare integer
  local anexit
  anexit="$(/bin/ls "$smokedir"/*.exit | head -1)"
  if /bin/grep -Eq '^[0-9]+$' "$anexit"; then
    pass "AC1 smoke emits run-NNN/smoke/{*.log,*.exit} with captured exit code"
  else
    fail "AC1 .exit file should hold a bare integer; got: $(cat "$anexit")"
  fi
  # merge-train evidence must be present (proves parallel flow was exercised)
  if /bin/ls "$smokedir"/merge-train*.log >/dev/null 2>&1; then
    pass "AC1 smoke exercised merge-train.sh (parallel flow validated e2e)"
  else
    fail "AC1 expected merge-train*.log proving the parallel flow ran"
  fi
  rm -rf "$ev"
}

# --- AC2: behavior preparer writes byte-stable sandboxed prompt ------------
ac2 () {
  local root skill rc
  root="$(mktemp -d)"
  mkdir -p "$root/.git" "$root/docs/dogfoods"
  set +e
  bash "$PREPARE" --repo-root "$root" --run-id 7 >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    fail "AC2 preparer --run-id 7 should exit 0 (got $rc)"; rm -rf "$root"; return
  fi
  local prompt="$root/docs/dogfoods/flow-dev/run-007/behavior/dispatch-prompt.md"
  if [[ ! -f "$prompt" ]]; then
    fail "AC2 expected $prompt"; rm -rf "$root"; return
  fi
  # HARD sandbox requirement (Open Q3)
  if /bin/grep -q 'feat/dogfood-run-007' "$prompt" \
     && /bin/grep -q -- '--worktree-ns dogfood-run-007' "$prompt"; then
    pass "AC2 prompt carries sandbox overrides (feat/dogfood-run-007 + --worktree-ns dogfood-run-007)"
  else
    fail "AC2 prompt missing sandbox overrides (Open Q3)"
  fi
  # byte-stability: regenerate the SAME run-id from a clean slate, diff empty.
  # The preparer refuses to overwrite an existing run dir (never-reuse rule),
  # so we must remove the whole run-007 dir before regenerating.
  local prompt2="$root/p2.md"
  cp "$prompt" "$prompt2"
  rm -rf "$root/docs/dogfoods/flow-dev/run-007"
  bash "$PREPARE" --repo-root "$root" --run-id 7 >/dev/null 2>&1
  if diff -q "$prompt" "$prompt2" >/dev/null 2>&1; then
    pass "AC2 prompt byte-stable across runs (same run-id -> identical bytes)"
  else
    fail "AC2 prompt NOT byte-stable"
  fi
  rm -rf "$root"
}

# --- AC3: run-id never reused (monotonic auto-detect) ----------------------
ac3 () {
  local root
  root="$(mktemp -d)"
  mkdir -p "$root/.git" "$root/docs/dogfoods"
  bash "$PREPARE" --repo-root "$root" >/dev/null 2>&1
  bash "$PREPARE" --repo-root "$root" >/dev/null 2>&1
  if [[ -d "$root/docs/dogfoods/flow-dev/run-001" \
     && -d "$root/docs/dogfoods/flow-dev/run-002" ]]; then
    pass "AC3 run-id monotonic (run-001 then run-002, never reused)"
  else
    fail "AC3 expected run-001 + run-002; got: $(/bin/ls "$root/docs/dogfoods/flow-dev" 2>/dev/null | tr '\n' ' ')"
  fi
  rm -rf "$root"
}

ac1
ac2
ac3

echo
echo "dogfood test: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]] || exit 1
