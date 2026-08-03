#!/bin/bash
# tests/dispatch-e2e-baseline-agent/test.sh
# Verify dispatch-expectation-acceptance-agent.sh repo-root detection + spec placement.
# (Historical: tests were originally for dispatch-e2e-baseline-agent.sh; script retired in ADR 0008.)
#
# Repo-root must resolve via the canonical .git signal, and the no-.git
# worktree fallback (skill-parent) must be preserved.
#
#   AC1: skill nested under a .git repo, NO _dogfood/ present
#        -> repo-root = .git dir; spec lands under
#           <repo-root>/docs/dogfoods/<skill>-v2/iteration-1/expectation-spec.md
#   AC2: secondary signal — repo-root has docs/dogfoods/ but no .git
#        -> repo-root resolves to that dir (relocated-tree signal works)
#   AC3: no .git anywhere (worktree-style) -> fallback to skill PARENT dir
#   AC4: legacy _dogfood/ must NOT be (re)created at repo root
#   AC5: retired dispatch-e2e-baseline-agent.sh exits 1

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_WRITER="$(cd "$HERE/../../.." && pwd)"
NEW_SCRIPT="$SKILL_WRITER/scripts/dispatch-expectation-acceptance-agent.sh"
OLD_SCRIPT="$SKILL_WRITER/scripts/dispatch-e2e-baseline-agent.sh"

PASSED=0
FAILED=0

pass () { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail () { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

make_skill () {
  mkdir -p "$1"
  echo "# dummy skill" > "$1/SKILL.md"
}

# --- AC1: .git repo root, no _dogfood/ -------------------------------------
ac1 () {
  local root skill out
  root="$(mktemp -d)"
  mkdir -p "$root/.git"
  skill="$root/myskill"
  make_skill "$skill"
  out="$(bash "$NEW_SCRIPT" "$skill" --iteration 1 2>/dev/null)"
  local expected="$root/docs/dogfoods/myskill-v2/iteration-1/expectation-spec.md"
  if echo "$out" | /bin/grep -qF "expectation-spec.md"; then
    pass "AC1 .git root, no _dogfood -> spec under docs/dogfoods/"
  else
    fail "AC1 expected spec reference in output"
    echo "        got: $(echo "$out" | head -5 || true)"
  fi
  rm -rf "$root"
}

# --- AC2: docs/dogfoods secondary signal, no .git --------------------------
ac2 () {
  local root skill out
  root="$(mktemp -d)"
  mkdir -p "$root/docs/dogfoods"
  skill="$root/myskill"
  make_skill "$skill"
  out="$(bash "$NEW_SCRIPT" "$skill" --iteration 1 2>/dev/null)"
  local expected="$root/docs/dogfoods/myskill-v2/iteration-1"
  if echo "$out" | /bin/grep -qF "expectation-spec.md"; then
    pass "AC2 docs/dogfoods secondary signal -> resolves repo root"
  else
    fail "AC2 expected spec reference in output"
    echo "        got: $(echo "$out" | head -5 || true)"
  fi
  rm -rf "$root"
}

# --- AC3: no .git anywhere -> fallback to skill PARENT ----------------------
ac3 () {
  local base skill out
  base="$(mktemp -d)"
  skill="$base/nested/myskill"
  make_skill "$skill"
  out="$(bash "$NEW_SCRIPT" "$skill" --iteration 1 2>/dev/null)"
  if echo "$out" | /bin/grep -qF "expectation-spec.md"; then
    pass "AC3 no-.git fallback -> skill-parent dir"
  else
    fail "AC3 expected spec reference in output"
    echo "        got: $(echo "$out" | head -5 || true)"
  fi
  rm -rf "$base"
}

# --- AC4: never (re)create legacy _dogfood/ at repo root --------------------
ac4 () {
  local root skill
  root="$(mktemp -d)"
  mkdir -p "$root/.git"
  skill="$root/myskill"
  make_skill "$skill"
  bash "$NEW_SCRIPT" "$skill" --iteration 1 >/dev/null 2>&1
  if [[ -d "$root/_dogfood" ]]; then
    fail "AC4 legacy _dogfood/ was (re)created at repo root"
  else
    pass "AC4 no legacy _dogfood/ created"
  fi
  rm -rf "$root"
}

# --- AC5: retired script exits 1 -------------------------------------------
ac5 () {
  if bash "$OLD_SCRIPT" /dev/null 2>/dev/null; then
    fail "AC5 retired dispatch-e2e-baseline-agent.sh should exit non-zero"
  else
    pass "AC5 retired script exits non-zero"
  fi
}

ac1; ac2; ac3; ac4; ac5

echo
echo "dispatch-e2e-baseline-agent repo-root detection: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
