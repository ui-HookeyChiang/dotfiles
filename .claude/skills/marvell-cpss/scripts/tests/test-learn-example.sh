#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# test-learn-example.sh — Offline tests for learn_example.sh
#
# Tests the template creation and placeholder replacement logic.
# No network access or device needed — all operations are local.
# =============================================================================

PASSED=0
FAILED=0
TESTS_RUN=()
TESTS_FAILED=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_pass() {
  PASSED=$((PASSED + 1))
  TESTS_RUN+=("PASS: $1")
  echo "  PASS: $1"
}

log_fail() {
  FAILED=$((FAILED + 1))
  TESTS_RUN+=("FAIL: $1")
  TESTS_FAILED+=("$1")
  echo "  FAIL: $1 — $2"
}

CLEANUP_FILES=()

# Resolve script under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEARN_EXAMPLE="$SCRIPT_DIR/learn_example.sh"

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

# Test 1: Missing argument → usage message + exit 1
test_missing_arg() {
  local test_name="missing_arg"
  echo "Running: $test_name"

  local output rc=0
  output=$(bash "$LEARN_EXAMPLE" 2>&1) || rc=$?

  if [ "$rc" -eq 0 ]; then
    log_fail "$test_name" "expected non-zero exit, got 0"
    return
  fi

  if ! echo "$output" | grep -qi "usage"; then
    log_fail "$test_name" "expected usage message, got: $output"
    return
  fi

  log_pass "$test_name"
}

# Test 2: Valid argument → creates a temp file (check it exists)
test_creates_temp_file() {
  local test_name="creates_temp_file"
  echo "Running: $test_name"

  local output rc=0
  output=$(bash "$LEARN_EXAMPLE" "test-example" 2>&1) || rc=$?

  if [ "$rc" -ne 0 ]; then
    log_fail "$test_name" "expected exit 0, got $rc: $output"
    return
  fi

  # Extract the temp file path from "Template created at: /tmp/..."
  local temp_file
  temp_file=$(echo "$output" | grep "Template created at:" | sed 's/Template created at: //')

  if [ -z "$temp_file" ]; then
    log_fail "$test_name" "could not find temp file path in output"
    return
  fi

  if [ ! -f "$temp_file" ]; then
    log_fail "$test_name" "temp file does not exist: $temp_file"
    return
  fi

  CLEANUP_FILES+=("$temp_file")
  log_pass "$test_name"
}

# Test 3: Template contains example name (sed replacement of [NAME])
test_name_replacement() {
  local test_name="name_replacement"
  echo "Running: $test_name"

  local example_name="port-mirroring"
  local output rc=0
  output=$(bash "$LEARN_EXAMPLE" "$example_name" 2>&1) || rc=$?

  local temp_file
  temp_file=$(echo "$output" | grep "Template created at:" | sed 's/Template created at: //')

  if [ -z "$temp_file" ] || [ ! -f "$temp_file" ]; then
    log_fail "$test_name" "temp file not found"
    return
  fi

  CLEANUP_FILES+=("$temp_file")

  # Check that [NAME] was replaced with the example name
  if ! grep -q "$example_name" "$temp_file"; then
    log_fail "$test_name" "example name '$example_name' not found in template"
    return
  fi

  # Check that no [NAME] placeholder remains
  if grep -q '\[NAME\]' "$temp_file"; then
    log_fail "$test_name" "[NAME] placeholder still present in template"
    return
  fi

  log_pass "$test_name"
}

# Test 4: Template has expected sections (Configuration Commands, What This Does, Validation)
test_template_sections() {
  local test_name="template_sections"
  echo "Running: $test_name"

  local output rc=0
  output=$(bash "$LEARN_EXAMPLE" "test-sections" 2>&1) || rc=$?

  local temp_file
  temp_file=$(echo "$output" | grep "Template created at:" | sed 's/Template created at: //')

  if [ -z "$temp_file" ] || [ ! -f "$temp_file" ]; then
    log_fail "$test_name" "temp file not found"
    return
  fi

  CLEANUP_FILES+=("$temp_file")

  local missing_sections=()

  if ! grep -q "Configuration Commands" "$temp_file"; then
    missing_sections+=("Configuration Commands")
  fi

  if ! grep -q "What This Does" "$temp_file"; then
    missing_sections+=("What This Does")
  fi

  if ! grep -q "Validation" "$temp_file"; then
    missing_sections+=("Validation")
  fi

  if [ "${#missing_sections[@]}" -gt 0 ]; then
    log_fail "$test_name" "missing sections: ${missing_sections[*]}"
    return
  fi

  log_pass "$test_name"
}

# Test 5: Script outputs correct "Next steps" instructions
test_next_steps_output() {
  local test_name="next_steps_output"
  echo "Running: $test_name"

  local output rc=0
  output=$(bash "$LEARN_EXAMPLE" "test-next-steps" 2>&1) || rc=$?

  # Extract temp file for cleanup
  local temp_file
  temp_file=$(echo "$output" | grep "Template created at:" | sed 's/Template created at: //')
  if [ -n "$temp_file" ] && [ -f "$temp_file" ]; then
    CLEANUP_FILES+=("$temp_file")
  fi

  if ! echo "$output" | grep -q "Next steps"; then
    log_fail "$test_name" "expected 'Next steps' in output"
    return
  fi

  if ! echo "$output" | grep -q "Edit the template"; then
    log_fail "$test_name" "expected 'Edit the template' instruction in output"
    return
  fi

  if ! echo "$output" | grep -q "Test the configuration"; then
    log_fail "$test_name" "expected 'Test the configuration' instruction in output"
    return
  fi

  log_pass "$test_name"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

cleanup() {
  for f in "${CLEANUP_FILES[@]}"; do
    rm -f "$f"
  done
}
trap cleanup EXIT

main() {
  echo "========================================="
  echo " test-learn-example.sh"
  echo "========================================="
  echo ""

  test_missing_arg
  test_creates_temp_file
  test_name_replacement
  test_template_sections
  test_next_steps_output

  echo ""
  echo "========================================="
  echo " Results: $PASSED passed, $FAILED failed"
  echo "========================================="

  if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for t in "${TESTS_FAILED[@]}"; do
      echo "  - $t"
    done
    exit 1
  fi

  exit 0
}

main "$@"
