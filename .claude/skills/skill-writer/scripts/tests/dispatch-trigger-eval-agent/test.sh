#!/bin/bash
# tests/dispatch-trigger-eval-agent/test.sh
# Verify dispatch-trigger-eval-agent.sh — the Phase 5 ADVISORY trigger-eval
# preparer (sibling of dispatch-dogfood-agent.sh).
#
# Hermetic: every case that needs the trigger_eval scripts directory either uses
# the real local one ($SKILL_WRITER/scripts/trigger_eval/) or stubs it out.
#
#   AC1 next-free run auto-detect: with run-005 present, the next preparer run
#       allocates run-006 (cumulative, never-reuse).
#   AC2 byte-stable prompt: two consecutive runs for the SAME skill+runs produce
#       byte-identical eval/dispatch-prompt.md (diff exit 0) AND distinct run dirs.
#   AC3 --help exits 0.
#   AC4 creates run-NNN/eval/ under docs/dogfoods/<skill>/ (resident path).
#   AC5 advisory skip (trigger_eval dir missing): when the trigger_eval/ dir is
#       absent the preparer does NOT hard-fail (exit 0) and emits
#       TRIGGER_EVAL_VERDICT=skip-no-trigger-eval.
#   AC6 advisory skip (no corpus): a skill with SKILL.md but NO
#       evals/trigger-eval.json does NOT hard-fail (exit 0) and emits
#       TRIGGER_EVAL_VERDICT=skip-no-corpus.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_WRITER="$(cd "$HERE/../../.." && pwd)"
SCRIPT="$SKILL_WRITER/scripts/dispatch-trigger-eval-agent.sh"

PASSED=0
FAILED=0
pass () { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail () { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

# make_skill <dir>: skill dir with SKILL.md + evals/trigger-eval.json.
make_skill () {
  mkdir -p "$1/evals"
  echo "# dummy skill" > "$1/SKILL.md"
  echo '{"cases":[]}' > "$1/evals/trigger-eval.json"
}

# make_skill_no_corpus <dir>: skill dir with SKILL.md but NO trigger corpus.
make_skill_no_corpus () {
  mkdir -p "$1"
  echo "# dummy skill" > "$1/SKILL.md"
}

# stub_trigger_eval <dir>: create a minimal trigger_eval/ stub at <dir>/trigger_eval/
# that satisfies the directory existence check in dispatch-trigger-eval-agent.sh.
# Used by AC1/AC2/AC4 via a symlink override of the scripts/ dir is not needed —
# those tests rely on the REAL trigger_eval/ dir shipped with skill-writer.

# --- AC1: next-free run auto-detect -----------------------------------------
ac1 () {
  local root skill
  root="$(mktemp -d)"; mkdir -p "$root/.git"
  skill="$root/myskill"; make_skill "$skill"
  mkdir -p "$root/docs/dogfoods/myskill/run-005/eval"
  bash "$SCRIPT" "$skill" >/dev/null 2>&1
  if [[ -d "$root/docs/dogfoods/myskill/run-006/eval" ]]; then
    pass "AC1 next-free auto-detect: run-005 present -> allocates run-006"
  else
    fail "AC1 expected run-006/eval to be created"
    echo "        got: $(ls -1d "$root"/docs/dogfoods/myskill/run-* 2>/dev/null | tr '\n' ' ')"
  fi
  rm -rf "$root"
}

# --- AC2: byte-stable prompt across two runs --------------------------------
ac2 () {
  local root skill p1 p2
  root="$(mktemp -d)"; mkdir -p "$root/.git"
  skill="$root/myskill"; make_skill "$skill"
  bash "$SCRIPT" "$skill" >/dev/null 2>&1
  bash "$SCRIPT" "$skill" >/dev/null 2>&1
  p1="$root/docs/dogfoods/myskill/run-001/eval/dispatch-prompt.md"
  p2="$root/docs/dogfoods/myskill/run-002/eval/dispatch-prompt.md"
  if [[ -f "$p1" && -f "$p2" ]]; then
    if diff "$p1" "$p2" >/dev/null 2>&1; then
      pass "AC2 byte-stable prompt: run-001 vs run-002 diff empty + distinct dirs"
    else
      fail "AC2 prompts differ between runs (must be byte-identical)"
      diff "$p1" "$p2" | sed 's/^/        /'
    fi
  else
    fail "AC2 expected dispatch-prompt.md in both run-001 and run-002"
    echo "        run dirs: $(ls -1d "$root"/docs/dogfoods/myskill/run-* 2>/dev/null | tr '\n' ' ')"
  fi
  rm -rf "$root"
}

# --- AC3: --help exits 0 ----------------------------------------------------
ac3 () {
  if bash "$SCRIPT" --help >/dev/null 2>&1; then
    pass "AC3 --help exits 0"
  else
    fail "AC3 --help should exit 0 (got $?)"
  fi
}

# --- AC4: creates run-NNN/eval/ resident path -------------------------------
ac4 () {
  local root skill
  root="$(mktemp -d)"; mkdir -p "$root/.git"
  skill="$root/myskill"; make_skill "$skill"
  bash "$SCRIPT" "$skill" >/dev/null 2>&1
  local ok=1
  [[ -d "$root/docs/dogfoods/myskill/run-001/eval" ]] || ok=0
  if compgen -G "$root/docs/dogfoods/myskill-v"* >/dev/null; then ok=0; fi
  if [[ $ok -eq 1 ]]; then
    pass "AC4 creates docs/dogfoods/myskill/run-001/eval, no -vN path"
  else
    fail "AC4 wrong layout"
    echo "        tree: $(ls -1dR "$root"/docs/dogfoods/* 2>/dev/null | tr '\n' ' ')"
  fi
  rm -rf "$root"
}

# --- AC5: advisory skip when trigger_eval dir missing -----------------------
ac5 () {
  local root skill tmpscripts out rc
  root="$(mktemp -d)"; mkdir -p "$root/.git"
  skill="$root/myskill"; make_skill "$skill"
  # Create a temporary scripts/ shim that has no trigger_eval/ dir, then
  # invoke the script from that shim's location so HERE resolves to it.
  tmpscripts="$(mktemp -d)"
  cp "$SCRIPT" "$tmpscripts/dispatch-trigger-eval-agent.sh"
  out="$(bash "$tmpscripts/dispatch-trigger-eval-agent.sh" "$skill" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q 'TRIGGER_EVAL_VERDICT=skip-no-trigger-eval'; then
    pass "AC5 missing trigger_eval dir -> advisory skip (exit 0 + skip verdict)"
  else
    fail "AC5 expected exit 0 + skip-no-trigger-eval verdict, got rc=$rc"
    echo "$out" | sed 's/^/        /'
  fi
  rm -rf "$root" "$tmpscripts"
}

# --- AC6: advisory skip when corpus not yet authored ------------------------
ac6 () {
  local root skill out rc
  root="$(mktemp -d)"; mkdir -p "$root/.git"
  skill="$root/myskill"; make_skill_no_corpus "$skill"   # SKILL.md but no evals/
  out="$(bash "$SCRIPT" "$skill" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q 'TRIGGER_EVAL_VERDICT=skip-no-corpus'; then
    pass "AC6 missing trigger-eval.json -> advisory skip (exit 0 + skip-no-corpus)"
  else
    fail "AC6 expected exit 0 + skip-no-corpus verdict, got rc=$rc"
    echo "$out" | sed 's/^/        /'
  fi
  rm -rf "$root"
}

ac1; ac2; ac3; ac4; ac5; ac6

echo
echo "dispatch-trigger-eval-agent preparer: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
