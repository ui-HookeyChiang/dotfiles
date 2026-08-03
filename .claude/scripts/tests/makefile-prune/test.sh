#!/usr/bin/env bash
# Regression test: `make test` / `make lint` discovery globs must NOT descend
# into nested git worktrees (.worktree/, .worktrees/, .claude/worktrees/).
#
# Before the WT_PRUNE fix, `find $(SKILLS_DIR) ... -name '*.sh'` recursed into
# every worktree dir living under the repo root, multiplying the real test set
# (~164 files) by the worktree count (1518 found with 9 worktrees) — each e2e
# test re-ran ~14x, hanging `make test` and burning CPU/disk.
#
# This test builds a synthetic SKILLS_DIR with a real test file plus a fake
# nested worktree containing a decoy test file, then runs the exact discovery
# find expression the Makefile uses (extracted from WT_PRUNE + the test glob)
# and asserts the decoy is excluded.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MAKEFILE="$REPO_ROOT/Makefile"

fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$MAKEFILE" ] || fail "Makefile not found at $MAKEFILE"

# Extract the WT_PRUNE definition value from the Makefile (single source of truth).
# Line form:  WT_PRUNE := \( -name .worktree ... \) -prune -o
WT_PRUNE_LINE="$(sed -n 's/^WT_PRUNE[[:space:]]*:=[[:space:]]*//p' "$MAKEFILE" | head -1)"
[ -n "$WT_PRUNE_LINE" ] || fail "Makefile defines no WT_PRUNE variable (prune clause missing)"

# Build a synthetic tree:
#   $TMP/skill-a/scripts/tests/real/test.sh         <- must be FOUND
#   $TMP/.worktrees/wt1/skill-b/scripts/tests/x/test.sh  <- must be EXCLUDED
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/skill-a/scripts/tests/real"
echo '#!/bin/bash' > "$TMP/skill-a/scripts/tests/real/test.sh"

mkdir -p "$TMP/.worktrees/wt1/skill-b/scripts/tests/x"
echo '#!/bin/bash' > "$TMP/.worktrees/wt1/skill-b/scripts/tests/x/test.sh"

mkdir -p "$TMP/.worktree/wt2/skill-c/scripts/tests/y"
echo '#!/bin/bash' > "$TMP/.worktree/wt2/skill-c/scripts/tests/y/test.sh"

# Fixture scripts under scripts/tests/fixtures/ are test INPUTS, not standalone
# tests — they must be EXCLUDED. (Real case: fp-refine-skill/scripts/{producer,
# consumer}.sh mutually recurse infinitely; auto-running them fork-bombs the box.)
mkdir -p "$TMP/skill-a/scripts/tests/fixtures/decoy/scripts"
echo '#!/bin/bash' > "$TMP/skill-a/scripts/tests/fixtures/decoy/scripts/producer.sh"

# Run the exact discovery find the Makefile `test` target uses, with WT_PRUNE
# spliced in. Note: -print is required because the `-prune -o` branch disables
# the implicit default print on the matched branch.
# shellcheck disable=SC2086
RESULT="$(eval find "$TMP" $WT_PRUNE_LINE \
  '\( -path "*/scripts/tests/*" -o -path "*/_shared/tests/*" -o -path "*/_shared/ci/tests/*" \)' \
  -not -path '"*/integration/*"' -not -path '"*/fixtures/*"' -type f '\( -name "*.sh" -o -name "*.lua" \)' -print | sort)"

echo "$RESULT" | grep -q "skill-a/scripts/tests/real/test.sh" \
  || fail "real test file was not discovered (prune over-excluded): $RESULT"

if echo "$RESULT" | grep -q "\.worktrees/wt1"; then
  fail ".worktrees/ nested worktree NOT excluded: $RESULT"
fi
if echo "$RESULT" | grep -q "\.worktree/wt2"; then
  fail ".worktree/ nested worktree NOT excluded: $RESULT"
fi
if echo "$RESULT" | grep -q "fixtures/decoy"; then
  fail "scripts/tests/fixtures/ decoy NOT excluded (fork-bomb risk): $RESULT"
fi

# The real Makefile `test` discovery glob must carry the fixtures exclusion.
grep -q "scripts/tests" "$MAKEFILE" || fail "Makefile lost the test discovery glob"
sed -n "/find \$(SKILLS_DIR).*scripts\/tests/p" "$MAKEFILE" | grep -q "fixtures" \
  || fail "Makefile test discovery glob missing -not -path '*/fixtures/*'"

# Exactly one file (the real one) must survive.
COUNT="$(echo "$RESULT" | grep -c 'test.sh')"
[ "$COUNT" -eq 1 ] || fail "expected exactly 1 discovered test, got $COUNT: $RESULT"

echo "PASS: WT_PRUNE excludes nested worktrees, keeps real tests ($COUNT found)"
