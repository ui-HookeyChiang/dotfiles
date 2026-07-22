#!/usr/bin/env bash
# Regression test for squash-merge.sh stack mode B1 (CI watch) block.
# Before B1.1 (2026-05-14), `gh pr checks --watch` was invoked unconditionally
# and its non-zero exit was interpreted as "CI failed". On repos with no
# check runs configured at all (e.g. no GitHub Actions), --watch also exits
# non-zero, so legitimately CI-less repos could not be auto-merged.
# This test is a lightweight structural guard: it asserts the probe code
# and skip-message log line are in place, and the script still parses.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../../squash-merge.sh"  # Sprint 2 unified rewrite: B1.1 fix now lives in unified script

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$TARGET" ]] || fail "squash-merge.sh not found at $TARGET"

# 1. Probe code is in place.
grep -q 'CHECK_COUNT=' "$TARGET" \
  || fail "expected CHECK_COUNT= probe in $TARGET (B1.1 fix missing)"

# 2. Skip-message log line is in place.
grep -q 'no CI configured for PR' "$TARGET" \
  || fail "expected 'no CI configured for PR' log line in $TARGET"

# 3. Script still parses.
bash -n "$TARGET" || fail "bash -n syntax check failed on $TARGET"

pass "ci-watch-no-checks"
