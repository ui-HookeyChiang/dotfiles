#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# test-merge-stack.sh — Tests for the flow-dev merge process
#
# Tests the rebase-stack logic using local git repos (bare repo as "origin"
# + working clone). No external dependencies except git.
#
# The merge process: rebase entire stack onto main, push rebased branches,
# update PR bases (skipped in tests — no GitHub). Does NOT auto-merge.
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

# Create a bare "origin" repo with an initial commit on main.
# Sets ORIGIN_DIR and WORK_DIR in the caller's scope.
setup_repos() {
  local tmpdir
  tmpdir=$(mktemp -d "/tmp/test-merge-stack.XXXXXX")
  CLEANUP_DIRS+=("$tmpdir")

  ORIGIN_DIR="$tmpdir/origin.git"
  WORK_DIR="$tmpdir/work"

  git init --bare "$ORIGIN_DIR" >/dev/null 2>&1
  git clone "$ORIGIN_DIR" "$WORK_DIR" >/dev/null 2>&1

  # Create initial commit so main exists
  pushd "$WORK_DIR" >/dev/null
  git checkout -b main >/dev/null 2>&1
  echo "initial" > README.md
  git add README.md
  git commit -m "initial commit" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
  popd >/dev/null
}

# Create stacked task branches.
#   create_stack <feature_prefix> <total_tasks> <commit_callback>
#
# commit_callback is called as: commit_callback $N $WORK_DIR
# It should create files, stage, and commit in $WORK_DIR (already cd'd there).
create_stack() {
  local feature_prefix="$1"
  local total_tasks="$2"
  local commit_callback="$3"

  pushd "$WORK_DIR" >/dev/null
  for N in $(seq 1 "$total_tasks"); do
    local base_branch
    if [ "$N" -eq 1 ]; then
      base_branch="main"
    else
      base_branch="${feature_prefix}/task-$((N - 1))"
    fi
    local task_branch="${feature_prefix}/task-${N}"

    git checkout -b "$task_branch" "$base_branch" >/dev/null 2>&1
    $commit_callback "$N" "$WORK_DIR"
    git push origin "$task_branch" >/dev/null 2>&1
  done
  git checkout main >/dev/null 2>&1
  popd >/dev/null
}

# ---------------------------------------------------------------------------
# Functions under test
# ---------------------------------------------------------------------------

# Rebase the entire stack onto latest main.
# For task-1: rebase onto origin/$default_branch
# For task-N>1: rebase onto origin/${feature_prefix}/task-$((N-1))
# After each rebase, push with --force-with-lease.
# Returns 0 on success, 1 on rebase conflict.
rebase_stack() {
  local work_dir="$1"
  local default_branch="$2"
  local feature_prefix="$3"
  local total_tasks="$4"

  pushd "$work_dir" >/dev/null
  git fetch origin >/dev/null 2>&1

  for N in $(seq 1 "$total_tasks"); do
    local task_branch="${feature_prefix}/task-${N}"

    git checkout "$task_branch" >/dev/null 2>&1

    local rebase_onto
    if [ "$N" -eq 1 ]; then
      rebase_onto="origin/$default_branch"
    else
      rebase_onto="origin/${feature_prefix}/task-$((N - 1))"
    fi

    if ! git rebase "$rebase_onto" >/dev/null 2>&1; then
      echo "Rebase conflict while rebasing task $N (${task_branch}) onto ${rebase_onto}." >&2
      git rebase --abort >/dev/null 2>&1 || true
      git checkout "$default_branch" >/dev/null 2>&1 || true
      popd >/dev/null
      return 1
    fi

    git push --force-with-lease origin "HEAD:refs/heads/${task_branch}" >/dev/null 2>&1
  done

  git checkout "$default_branch" >/dev/null 2>&1
  popd >/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

test_happy_path_3_tasks() {
  local test_name="happy_path_3_tasks"
  echo "Running: $test_name"

  setup_repos

  local feature_prefix="feat/test"
  local total_tasks=3

  _happy_commit() {
    local n="$1"
    echo "task-${n}-content" > "task-${n}.txt"
    git add "task-${n}.txt"
    git commit -m "feat: implement task $n" >/dev/null 2>&1
  }

  create_stack "$feature_prefix" "$total_tasks" _happy_commit

  # Rebase stack onto main
  if ! rebase_stack "$WORK_DIR" "main" "$feature_prefix" "$total_tasks"; then
    log_fail "$test_name" "rebase_stack failed unexpectedly"
    return
  fi

  pushd "$WORK_DIR" >/dev/null
  git fetch origin >/dev/null 2>&1

  # All task branches should be descendants of main
  for N in 1 2 3; do
    if ! git merge-base --is-ancestor "origin/main" "origin/${feature_prefix}/task-${N}" 2>/dev/null; then
      log_fail "$test_name" "task-$N is not a descendant of main"
      popd >/dev/null
      return
    fi
  done

  # Final task branch should have all files
  git checkout "origin/${feature_prefix}/task-3" >/dev/null 2>&1
  for N in 1 2 3; do
    if [ ! -f "task-${N}.txt" ]; then
      log_fail "$test_name" "task-${N}.txt missing from final task branch"
      popd >/dev/null
      return
    fi
    local content
    content=$(cat "task-${N}.txt")
    if [ "$content" != "task-${N}-content" ]; then
      log_fail "$test_name" "task-${N}.txt has wrong content"
      popd >/dev/null
      return
    fi
  done

  # Each task branch has only its own changes on top of the previous
  for N in 1 2 3; do
    local base_ref
    if [ "$N" -eq 1 ]; then
      base_ref="origin/main"
    else
      base_ref="origin/${feature_prefix}/task-$((N - 1))"
    fi
    local diff_files
    diff_files=$(git diff --name-only "${base_ref}..origin/${feature_prefix}/task-${N}")
    if [ "$diff_files" != "task-${N}.txt" ]; then
      log_fail "$test_name" "task-$N diff should only contain task-${N}.txt, got: $diff_files"
      popd >/dev/null
      return
    fi
  done

  popd >/dev/null
  log_pass "$test_name"
}

test_main_diverged_auto_rebase() {
  local test_name="main_diverged_auto_rebase"
  echo "Running: $test_name"

  setup_repos

  local feature_prefix="feat/diverge"
  local total_tasks=2

  _diverge_commit() {
    local n="$1"
    echo "diverge-task-${n}" > "task-${n}.txt"
    git add "task-${n}.txt"
    git commit -m "feat: task $n" >/dev/null 2>&1
  }

  create_stack "$feature_prefix" "$total_tasks" _diverge_commit

  # Add a non-conflicting commit to main on origin
  pushd "$WORK_DIR" >/dev/null
  git checkout main >/dev/null 2>&1
  git pull origin main >/dev/null 2>&1
  echo "divergent change" > divergent.txt
  git add divergent.txt
  git commit -m "chore: unrelated change on main" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
  popd >/dev/null

  # Rebase should succeed (auto-rebase handles divergence)
  if ! rebase_stack "$WORK_DIR" "main" "$feature_prefix" "$total_tasks"; then
    log_fail "$test_name" "rebase_stack should succeed with non-conflicting divergence"
    return
  fi

  pushd "$WORK_DIR" >/dev/null
  git fetch origin >/dev/null 2>&1

  # All task branches should include main's new commit (be descendants of main)
  for N in 1 2; do
    if ! git merge-base --is-ancestor "origin/main" "origin/${feature_prefix}/task-${N}" 2>/dev/null; then
      log_fail "$test_name" "task-$N should be a descendant of updated main"
      popd >/dev/null
      return
    fi
  done

  # All task files still present on final branch
  git checkout "origin/${feature_prefix}/task-2" >/dev/null 2>&1
  for N in 1 2; do
    if [ ! -f "task-${N}.txt" ]; then
      log_fail "$test_name" "task-${N}.txt missing after rebase"
      popd >/dev/null
      return
    fi
  done

  # Main's divergent file should also be present (rebased on top of it)
  if [ ! -f "divergent.txt" ]; then
    log_fail "$test_name" "divergent.txt from main should be present on rebased branch"
    popd >/dev/null
    return
  fi

  popd >/dev/null
  log_pass "$test_name"
}

test_rebase_conflict() {
  local test_name="rebase_conflict"
  echo "Running: $test_name"

  setup_repos

  local feature_prefix="feat/conflict"

  # Create a stack where task-1 creates shared.txt, task-2 modifies it.
  # Then add a conflicting change to main before rebasing.
  pushd "$WORK_DIR" >/dev/null

  # Task 1: create shared.txt
  git checkout -b "${feature_prefix}/task-1" main >/dev/null 2>&1
  printf "line1\nline2\nline3\nline4\nline5\n" > shared.txt
  git add shared.txt
  git commit -m "feat: task 1 creates shared.txt" >/dev/null 2>&1
  git push origin "${feature_prefix}/task-1" >/dev/null 2>&1

  # Task 2: modify the middle of shared.txt (stacked on task-1)
  git checkout -b "${feature_prefix}/task-2" "${feature_prefix}/task-1" >/dev/null 2>&1
  printf "line1\nline2\ntask2-changed-line3\nline4\nline5\n" > shared.txt
  git add shared.txt
  git commit -m "feat: task 2 modifies shared.txt" >/dev/null 2>&1
  git push origin "${feature_prefix}/task-2" >/dev/null 2>&1

  # Add conflicting commit to main (modifies the same line task-1 creates)
  git checkout main >/dev/null 2>&1
  printf "line1\nline2\nhotfix-changed-line3\nline4\nline5\n" > shared.txt
  git add shared.txt
  git commit -m "fix: hotfix modifies shared.txt on main" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  popd >/dev/null

  # Rebase should fail with conflict (task-1 creates shared.txt which conflicts
  # with main's version of shared.txt)
  local err_output
  if err_output=$(rebase_stack "$WORK_DIR" "main" "$feature_prefix" 2 2>&1); then
    log_fail "$test_name" "rebase_stack should have failed with conflict"
    return
  fi

  if echo "$err_output" | grep -q "Rebase conflict"; then
    log_pass "$test_name"
  else
    log_fail "$test_name" "error should mention 'Rebase conflict', got: $err_output"
  fi
}

test_single_task() {
  local test_name="single_task"
  echo "Running: $test_name"

  setup_repos

  local feature_prefix="feat/single"

  _single_commit() {
    local n="$1"
    echo "single-content" > "only-file.txt"
    git add "only-file.txt"
    git commit -m "feat: the only task" >/dev/null 2>&1
  }

  create_stack "$feature_prefix" 1 _single_commit

  # Rebase stack
  if ! rebase_stack "$WORK_DIR" "main" "$feature_prefix" 1; then
    log_fail "$test_name" "rebase_stack failed unexpectedly"
    return
  fi

  pushd "$WORK_DIR" >/dev/null
  git fetch origin >/dev/null 2>&1

  # Branch should be descendant of main
  if ! git merge-base --is-ancestor "origin/main" "origin/${feature_prefix}/task-1" 2>/dev/null; then
    log_fail "$test_name" "task-1 is not a descendant of main"
    popd >/dev/null
    return
  fi

  # File should be present with correct content
  git checkout "origin/${feature_prefix}/task-1" >/dev/null 2>&1
  if [ -f "only-file.txt" ] && [ "$(cat only-file.txt)" = "single-content" ]; then
    log_pass "$test_name"
  else
    log_fail "$test_name" "only-file.txt missing or wrong content"
  fi
  popd >/dev/null
}

test_multi_commit_task() {
  local test_name="multi_commit_task"
  echo "Running: $test_name"

  setup_repos

  local feature_prefix="feat/multi"

  # Task 1: single commit (base)
  # Task 2: three commits, each adding a file
  _multi_commit() {
    local n="$1"
    local wd="$2"
    if [ "$n" -eq 1 ]; then
      echo "base" > base.txt
      git add base.txt
      git commit -m "feat: task 1 base" >/dev/null 2>&1
    else
      echo "multi-a" > multi-a.txt
      git add multi-a.txt
      git commit -m "feat: task 2 part a" >/dev/null 2>&1

      echo "multi-b" > multi-b.txt
      git add multi-b.txt
      git commit -m "feat: task 2 part b" >/dev/null 2>&1

      echo "multi-c" > multi-c.txt
      git add multi-c.txt
      git commit -m "feat: task 2 part c" >/dev/null 2>&1
    fi
  }

  create_stack "$feature_prefix" 2 _multi_commit

  # Record SHAs before rebase
  pushd "$WORK_DIR" >/dev/null
  git fetch origin >/dev/null 2>&1
  local sha_task1 sha_task2
  sha_task1=$(git rev-parse "origin/${feature_prefix}/task-1")
  sha_task2=$(git rev-parse "origin/${feature_prefix}/task-2")

  # Verify task 2 has exactly 3 unique commits before rebase
  local commit_count
  commit_count=$(git log --format="%H" "${sha_task1}..${sha_task2}" | wc -l | tr -d ' ')
  if [ "$commit_count" -ne 3 ]; then
    log_fail "$test_name" "expected 3 unique commits for task 2 before rebase, got $commit_count"
    popd >/dev/null
    return
  fi
  popd >/dev/null

  # Rebase stack
  if ! rebase_stack "$WORK_DIR" "main" "$feature_prefix" 2; then
    log_fail "$test_name" "rebase_stack failed"
    return
  fi

  # Verify all commits survived the rebase in order
  pushd "$WORK_DIR" >/dev/null
  git fetch origin >/dev/null 2>&1

  # Task 2 should still have 3 commits on top of task 1
  local post_commit_count
  post_commit_count=$(git log --format="%H" "origin/${feature_prefix}/task-1..origin/${feature_prefix}/task-2" | wc -l | tr -d ' ')
  if [ "$post_commit_count" -ne 3 ]; then
    log_fail "$test_name" "expected 3 commits for task 2 after rebase, got $post_commit_count"
    popd >/dev/null
    return
  fi

  # Verify commit messages are in order
  local messages
  messages=$(git log --format="%s" --reverse "origin/${feature_prefix}/task-1..origin/${feature_prefix}/task-2")
  local expected
  expected=$(printf "feat: task 2 part a\nfeat: task 2 part b\nfeat: task 2 part c")
  if [ "$messages" != "$expected" ]; then
    log_fail "$test_name" "commit messages out of order after rebase"
    popd >/dev/null
    return
  fi

  # Verify all files present with correct content on final branch
  git checkout "origin/${feature_prefix}/task-2" >/dev/null 2>&1

  local ok=true
  for f in base.txt multi-a.txt multi-b.txt multi-c.txt; do
    if [ ! -f "$f" ]; then
      ok=false
      break
    fi
  done

  if [ "$ok" = true ] &&
     [ "$(cat multi-a.txt)" = "multi-a" ] &&
     [ "$(cat multi-b.txt)" = "multi-b" ] &&
     [ "$(cat multi-c.txt)" = "multi-c" ]; then
    log_pass "$test_name"
  else
    log_fail "$test_name" "files missing or content incorrect after rebase"
  fi
  popd >/dev/null
}

test_no_merge_happens() {
  local test_name="no_merge_happens"
  echo "Running: $test_name"

  setup_repos

  local feature_prefix="feat/nomerge"
  local total_tasks=2

  _nomerge_commit() {
    local n="$1"
    echo "nomerge-task-${n}" > "task-${n}.txt"
    git add "task-${n}.txt"
    git commit -m "feat: task $n" >/dev/null 2>&1
  }

  create_stack "$feature_prefix" "$total_tasks" _nomerge_commit

  # Record main's commit log before rebase
  pushd "$WORK_DIR" >/dev/null
  git fetch origin >/dev/null 2>&1
  local main_log_before
  main_log_before=$(git log --oneline "origin/main")
  popd >/dev/null

  # Rebase stack
  if ! rebase_stack "$WORK_DIR" "main" "$feature_prefix" "$total_tasks"; then
    log_fail "$test_name" "rebase_stack failed unexpectedly"
    return
  fi

  # Verify main has NOT changed (no new commits)
  pushd "$WORK_DIR" >/dev/null
  git fetch origin >/dev/null 2>&1
  local main_log_after
  main_log_after=$(git log --oneline "origin/main")

  if [ "$main_log_before" = "$main_log_after" ]; then
    log_pass "$test_name"
  else
    log_fail "$test_name" "main should not have changed after rebase_stack"
  fi
  popd >/dev/null
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

CLEANUP_DIRS=()

cleanup() {
  for dir in "${CLEANUP_DIRS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

main() {
  echo "========================================="
  echo " test-merge-stack.sh"
  echo "========================================="
  echo ""

  test_happy_path_3_tasks
  test_main_diverged_auto_rebase
  test_rebase_conflict
  test_single_task
  test_multi_commit_task
  test_no_merge_happens

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
