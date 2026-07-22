#!/bin/bash
# tests/dispatch-dogfood-agent/test.sh
# Verify dispatch-dogfood-agent.sh — the resident-dogfood Behavior-depth
# preparer (sibling of dispatch-e2e-baseline-agent.sh, NOT an extension of it).
#
# Contract under test (PR2 of resident-dogfood; PR1 contract in
# docs/dogfoods/README.md Part 2):
#
#   AC1 next-free run auto-detect: with run-005 already present, the next
#       preparer run allocates run-006 (cumulative, never-reuse).
#   AC2 byte-stable prompt: two consecutive runs for the SAME skill+task
#       produce byte-identical behavior/dispatch-prompt.md (diff exit 0)
#       AND distinct run dirs (run-001 then run-002).
#   AC3 --help exits 0.
#   AC4 creates run-NNN under docs/dogfoods/<skill>/ (resident path, NO -vN
#       suffix) — NOT a legacy <skill>-v2/iteration-M/ rewrite path.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_WRITER="$(cd "$HERE/../../.." && pwd)"
SCRIPT="$SKILL_WRITER/scripts/dispatch-dogfood-agent.sh"

PASSED=0
FAILED=0

pass () { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail () { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

make_skill () {
  # $1 = skill dir to create with a SKILL.md
  mkdir -p "$1"
  echo "# dummy skill" > "$1/SKILL.md"
}

# --- AC1: next-free run auto-detect ----------------------------------------
ac1 () {
  local root skill
  root="$(mktemp -d)"
  mkdir -p "$root/.git"
  skill="$root/myskill"
  make_skill "$skill"
  # Pre-seed an existing run-005; next allocation must be run-006.
  mkdir -p "$root/docs/dogfoods/myskill/run-005/behavior"
  bash "$SCRIPT" "$skill" --task "do X" >/dev/null 2>&1
  if [[ -d "$root/docs/dogfoods/myskill/run-006" ]]; then
    pass "AC1 next-free auto-detect: run-005 present -> allocates run-006"
  else
    fail "AC1 expected run-006 to be created"
    echo "        got: $(ls -1d "$root"/docs/dogfoods/myskill/run-* 2>/dev/null | tr '\n' ' ')"
  fi
  rm -rf "$root"
}

# --- AC2: byte-stable prompt across two runs -------------------------------
ac2 () {
  local root skill p1 p2
  root="$(mktemp -d)"
  mkdir -p "$root/.git"
  skill="$root/myskill"
  make_skill "$skill"
  bash "$SCRIPT" "$skill" --task "run the smoke fixture" >/dev/null 2>&1
  bash "$SCRIPT" "$skill" --task "run the smoke fixture" >/dev/null 2>&1
  p1="$root/docs/dogfoods/myskill/run-001/behavior/dispatch-prompt.md"
  p2="$root/docs/dogfoods/myskill/run-002/behavior/dispatch-prompt.md"
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

# --- AC4: creates resident run-NNN path, NOT legacy -vN/iteration ----------
ac4 () {
  local root skill
  root="$(mktemp -d)"
  mkdir -p "$root/.git"
  skill="$root/myskill"
  make_skill "$skill"
  bash "$SCRIPT" "$skill" --task "do X" >/dev/null 2>&1
  local ok=1
  # resident run path must exist
  [[ -d "$root/docs/dogfoods/myskill/run-001/inputs" ]] || ok=0
  [[ -d "$root/docs/dogfoods/myskill/run-001/behavior" ]] || ok=0
  # legacy rewrite path must NOT be created
  if compgen -G "$root/docs/dogfoods/myskill-v"* >/dev/null; then ok=0; fi
  if [[ $ok -eq 1 ]]; then
    pass "AC4 creates docs/dogfoods/myskill/run-001/{inputs,behavior}, no -vN path"
  else
    fail "AC4 wrong layout"
    echo "        tree: $(ls -1dR "$root"/docs/dogfoods/* 2>/dev/null | tr '\n' ' ')"
  fi
  rm -rf "$root"
}

ac1; ac2; ac3; ac4

echo
echo "dispatch-dogfood-agent preparer: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
