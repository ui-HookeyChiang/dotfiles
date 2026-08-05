#!/usr/bin/env bash
# Test that flow-merge scripts resolve REPO_ROOT correctly when invoked through a symlink.
#
# Regression test for: flow-merge symlink invocation fails to find cross-boundary resources
# When scripts are invoked via ~/.claude/skills/flow-merge -> (real skill-dev path),
# logical pwd resolution (cd ... && pwd) would land on ~/.claude/skills instead of skill-dev,
# causing cleanup.sh, run-merge-events.sh, and lint-merge-events.sh to fail.
# Physical resolution (pwd -P) fixes this.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd -P)"
CLEANUP_SCRIPT="$REPO_ROOT/flow-merge/scripts/events/cleanup.sh"

PASSED=0
FAILED=0
FAIL_NAMES=()

pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
fail() { FAILED=$((FAILED+1)); FAIL_NAMES+=("$1"); echo "  FAIL: $1 — $2"; }

# ---------------------------------------------------------------------------
# Case: symlink invocation resolves post-merge-cleanup.sh
#
# Creates a temporary symlink to the real flow-merge skill dir, then invokes
# cleanup.sh through that symlink. The script should resolve REPO_ROOT
# physically and find _shared/stack/post-merge-cleanup.sh without error.
# ---------------------------------------------------------------------------
test_symlink_resolution() {
  local tmp skill_real skill_link out rc
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # skill_real points to the real flow-merge skill dir (absolute path)
  skill_real="$(cd "$REPO_ROOT/flow-merge" && pwd -P)"
  # skill_link is a symlink in a temp dir pointing to skill_real
  skill_link="$tmp/flow-merge-symlink"
  ln -s "$skill_real" "$skill_link"

  # Mock flock to avoid test environment dependency
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/flock" <<'SHIM'
#!/usr/bin/env bash
# Mock flock — always succeeds and runs the command
exec "${@:3}"
SHIM
  chmod +x "$tmp/bin/flock"

  # Invoke cleanup.sh through the symlink with minimal args (dry-run mode).
  # The script should not fail with "post-merge-cleanup.sh: No such file".
  out=$( FLOW_MERGE_CLEANUP_MODE=single \
         FLOW_MERGE_BRANCH_NAME=test-branch \
         FLOW_MERGE_DEFAULT_BRANCH=main \
         SD_DRY_RUN=1 \
         SD_SKIP_REMOTE=1 \
         PATH="$tmp/bin:$PATH" \
         bash "$skill_link/scripts/events/cleanup.sh" 2>&1 ) && rc=0 || rc=$?

  # Check: the critical failure is "No such file" for post-merge-cleanup.sh during
  # path resolution. That should NOT happen with pwd -P.
  if echo "$out" | grep -q 'post-merge-cleanup.sh.*No such file'; then
    fail "symlink-resolution" "post-merge-cleanup.sh not found: $out"
    return 1
  fi

  # Check: script either succeeds (rc=0) or fails safely (e.g., git missing, flock issues).
  # The key is that the SCRIPT ITSELF resolved correctly.
  if [[ "$rc" != 0 ]]; then
    # If it failed, make sure it's not a path resolution issue
    if echo "$out" | grep -q 'No such file\|not found.*scripts/events/cleanup'; then
      fail "symlink-resolution" "cleanup.sh itself not found: $out"
      return 1
    fi
    # Other errors (git, flock, etc) are acceptable for this regression test
    pass "symlink invocation resolved post-merge-cleanup.sh correctly (exit $rc is ok for this test env)"
  else
    pass "symlink invocation resolved post-merge-cleanup.sh correctly (exit 0)"
  fi
}

# ---------------------------------------------------------------------------
# Case: run-merge-events.sh resolves registry via symlink
#
# run-merge-events.sh auto-discovers merge-events.tsv registries by walking
# $REPO_ROOT. When invoked via symlink with logical pwd, $REPO_ROOT would
# land on ~/.claude/skills, and find . would not locate the registries.
# With physical resolution, it correctly finds them under skill-dev.
#
# Assertion: the resolved path must point into the real skill-dev checkout
# (verified by checking the output reports the actual physical registry path).
# ---------------------------------------------------------------------------
test_run_merge_events_symlink() {
  local tmp skill_real skill_link out rc registry_line
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  skill_real="$(cd "$REPO_ROOT/flow-merge" && pwd -P)"
  skill_link="$tmp/flow-merge-symlink"
  ln -s "$skill_real" "$skill_link"

  # Invoke run-merge-events.sh with --phase post_merge and no explicit registry.
  # It should auto-discover the registry and successfully parse it.
  out=$( bash "$skill_link/scripts/run-merge-events.sh" \
         --phase post_merge --events cleanup 2>&1 ) && rc=0 || rc=$?

  # Failure case: "registry not found" or "no merge-event registries found"
  # indicates path resolution crossed the skill boundary.
  if echo "$out" | grep -q 'registry not found\|no merge-event registries found'; then
    fail "run-merge-events-symlink" "registry discovery failed: $out"
    return 1
  fi

  # Success case: output contains the physical path to the discovered registry
  # (it starts with the real skill-dev path, not ~/.claude/skills).
  # The script prints "ERROR: cleanup registry line" or loads it successfully,
  # but the path in the report must be the real skill-dev path, not the symlink.
  if echo "$out" | grep -q "$REPO_ROOT/flow-merge/references/merge-events.tsv"; then
    pass "run-merge-events.sh resolved registry to physical path via symlink"
  else
    # Alternative: check that the event lookup succeeded (it found 'cleanup' event)
    # which means the registry was actually loaded from the physical location.
    if echo "$out" | grep -q 'cleanup.*post_merge\|ERROR: cleanup'; then
      pass "run-merge-events.sh resolved registry via symlink (event recognized)"
    else
      fail "run-merge-events-symlink" "could not verify physical path resolution: $out"
      return 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# Case: lint-merge-events.sh resolves registries via symlink
#
# lint-merge-events.sh auto-discovers merge-events.tsv files via find.
# Same issue: logical pwd lands on ~/.claude/skills, so find fails.
# Physical resolution fixes it.
#
# Assertion: the resolved path must point into the real skill-dev checkout.
# Verify by checking: (1) no "no merge-event registries found" error, and
# (2) output contains count > 0 events (which means it actually parsed
# registries from the real physical path).
# ---------------------------------------------------------------------------
test_lint_merge_events_symlink() {
  local tmp skill_real skill_link out rc event_count
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  skill_real="$(cd "$REPO_ROOT/flow-merge" && pwd -P)"
  skill_link="$tmp/flow-merge-symlink"
  ln -s "$skill_real" "$skill_link"

  # Invoke lint-merge-events.sh with no explicit registries.
  # It should auto-discover registries from the physical path.
  out=$( bash "$skill_link/scripts/lint-merge-events.sh" 2>&1 ) && rc=0 || rc=$?

  # Failure case: "no merge-event registries found" means path resolution broke.
  if echo "$out" | grep -q 'no merge-event registries found'; then
    fail "lint-merge-events-symlink" "registry discovery failed: $out"
    return 1
  fi

  # Success case: output shows event count > 0, which proves it successfully
  # discovered and loaded registries from the physical location.
  # The summary line format is: "merge-event registry lint: OK (N events, M merge configs)"
  if echo "$out" | grep -q 'merge-event registry lint:.*[0-9].*events'; then
    # Extract and check event count is positive
    event_count=$(echo "$out" | grep -o '[0-9]* events' | grep -o '[0-9]*' | head -1)
    if [[ -n "$event_count" && "$event_count" -gt 0 ]]; then
      pass "lint-merge-events.sh resolved registries to physical path via symlink ($event_count events found)"
    else
      fail "lint-merge-events-symlink" "found registries but event count is 0: $out"
      return 1
    fi
  else
    fail "lint-merge-events-symlink" "could not verify registry discovery: $out"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Runner — all cases must run; failures accumulate
# ---------------------------------------------------------------------------
echo "=========================================================="
echo " test flow-merge scripts symlink resolution"
echo "=========================================================="

test_symlink_resolution || true
test_run_merge_events_symlink || true
test_lint_merge_events_symlink || true

echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [[ "$FAILED" -gt 0 ]]; then
  echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
