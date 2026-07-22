#!/bin/bash
# tests/dispatch-e2e-baseline-agent/test.sh
# Verify dispatch-e2e-baseline-agent.sh repo-root detection + snapshot placement AFTER
# the _dogfood/ -> docs/dogfoods/ relocation. Repo-root must resolve via the
# canonical .git signal (NOT the now-gone _dogfood/ dir), and the no-.git
# worktree fallback (skill-parent) must be preserved.
#
#   AC1: skill nested under a .git repo, NO _dogfood/ present
#        -> repo-root = .git dir; snapshot lands under
#           <repo-root>/docs/dogfoods/<skill>-v2/iteration-1/v1-snapshot/
#   AC2: secondary signal — repo-root has docs/dogfoods/ but no .git
#        -> repo-root resolves to that dir (relocated-tree signal works)
#   AC3: no .git anywhere (worktree-style) -> fallback to skill PARENT dir
#challenge AC4: legacy _dogfood/ must NOT be (re)created at repo root

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_WRITER="$(cd "$HERE/../../.." && pwd)"
SCRIPT="$SKILL_WRITER/scripts/dispatch-e2e-baseline-agent.sh"

PASSED=0
FAILED=0

pass () { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail () { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

make_skill () {
  # $1 = skill dir to create with a SKILL.md
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
  out="$(bash "$SCRIPT" "$skill" --iteration 1 2>/dev/null)"
  local expected="$root/docs/dogfoods/myskill-v2/iteration-1/v1-snapshot"
  if echo "$out" | /bin/grep -qF "$expected"; then
    pass "AC1 .git root, no _dogfood -> snapshot under docs/dogfoods/"
  else
    fail "AC1 expected snapshot at $expected"
    echo "        got: $(echo "$out" | /bin/grep -F 'v1 snapshot:' || true)"
  fi
  rm -rf "$root"
}

# --- AC2: docs/dogfoods secondary signal, no .git --------------------------
ac2 () {
  local root skill out
  root="$(mktemp -d)"
  mkdir -p "$root/docs/dogfoods"   # relocated-tree signal, no .git
  skill="$root/myskill"
  make_skill "$skill"
  out="$(bash "$SCRIPT" "$skill" --iteration 1 2>/dev/null)"
  local expected="$root/docs/dogfoods/myskill-v2/iteration-1/v1-snapshot"
  if echo "$out" | /bin/grep -qF "$expected"; then
    pass "AC2 docs/dogfoods secondary signal -> resolves repo root"
  else
    fail "AC2 expected snapshot at $expected"
    echo "        got: $(echo "$out" | /bin/grep -F 'v1 snapshot:' || true)"
  fi
  rm -rf "$root"
}

# --- AC3: no .git anywhere -> fallback to skill PARENT ----------------------
ac3 () {
  local base skill out
  base="$(mktemp -d)"   # NOTE: /tmp has no .git up the chain in CI sandboxes
  skill="$base/nested/myskill"
  make_skill "$skill"
  out="$(bash "$SCRIPT" "$skill" --iteration 1 2>/dev/null)"
  # fallback REPO_ROOT = dirname(skill) = $base/nested
  local expected="$base/nested/docs/dogfoods/myskill-v2/iteration-1/v1-snapshot"
  if echo "$out" | /bin/grep -qF "$expected"; then
    pass "AC3 no-.git fallback -> skill-parent dir"
  else
    fail "AC3 expected fallback snapshot at $expected"
    echo "        got: $(echo "$out" | /bin/grep -F 'v1 snapshot:' || true)"
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
  bash "$SCRIPT" "$skill" --iteration 1 >/dev/null 2>&1
  if [[ -d "$root/_dogfood" ]]; then
    fail "AC4 legacy _dogfood/ was (re)created at repo root"
  else
    pass "AC4 no legacy _dogfood/ created"
  fi
  rm -rf "$root"
}

ac1; ac2; ac3; ac4

echo
echo "dispatch-e2e-baseline-agent repo-root detection: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
