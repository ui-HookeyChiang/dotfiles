#!/bin/bash
# merge-train-cwd-independence/test.sh
#
# Regression tests for two parallel-stacks bugs surfaced by the run-002
# resident dogfood (see docs/dogfoods/flow-dev/run-002/behavior/gaps.md):
#
#   F1 — merge-train.sh built INT_DIR from a RELATIVE ".worktrees/..." path.
#        When invoked from inside a leaf worktree (a documented Phase 3 entry
#        point), the relative path resolved under the LEAF's cwd, creating a
#        nested integration worktree at <leaf>/.worktrees/.../integration
#        instead of <repo-root>/.worktrees/.../integration.
#
#   F2 — merge-train.sh rebased EVERY layer including layer-1, but by Phase 3
#        layer-1 is already squash-merged into the default branch. Replaying
#        its pre-squash commits onto an integration branch built FROM the
#        default branch (which already contains the squashed equivalent)
#        produced a same-content/different-hash rebase conflict.
#
# Assertions check real git/filesystem state, not log strings.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/stack/merge-train.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS [$1]"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL [$1] — $2" >&2; }

git_q() { git -c user.email=t@t -c user.name=t "$@"; }

# Build a repo with an origin remote so origin/<default> exists (F2 detection
# relies on comparing leaves against the merged default branch).
make_repo() {
  local tmp="$1"
  git init --bare -q "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/main" 2>/dev/null
  cd "$tmp/main"
  git config user.email t@t; git config user.name t
  git checkout -q -b main 2>/dev/null || git checkout -q main
  echo base > base.txt
  git_q add base.txt; git_q commit -q -m base
  git push -q origin main
}

# ---------------------------------------------------------------------------
# F1: invoke merge-train from INSIDE a leaf worktree; integration worktree
#     must land at <repo-root>/.worktrees/<ns>/integration, NOT nested under
#     the leaf.
# ---------------------------------------------------------------------------
test_f1_cwd_independence() {
  local tmp rc; tmp=$(mktemp -d)
  ( make_repo "$tmp"
    cd "$tmp/main"
    for g in PR-1 PR-2; do
      git_q branch "feat/foo/task-${g}" main
      git worktree add -q ".worktrees/feat-foo/task-${g}" "feat/foo/task-${g}"
    done
    echo a > .worktrees/feat-foo/task-PR-1/a.txt
    ( cd .worktrees/feat-foo/task-PR-1 && git_q add a.txt && git_q commit -q -m "feat: a" )
    echo b > .worktrees/feat-foo/task-PR-2/b.txt
    ( cd .worktrees/feat-foo/task-PR-2 && git_q add b.txt && git_q commit -q -m "feat: b" )

    # Invoke FROM the leaf worktree (the bug trigger).
    cd "$tmp/main/.worktrees/feat-foo/task-PR-1"
    SD_PARALLEL_LAYERS='[["PR-1"],["PR-2"]]' \
      bash "$SCRIPT" --feature-prefix feat/foo --worktree-ns feat-foo --default-branch main >/dev/null 2>&1

    # Correct location must exist; nested wrong location must NOT.
    [[ -d "$tmp/main/.worktrees/feat-foo/integration" ]] || { echo "MISSING-ROOT"; exit 3; }
    [[ ! -d "$tmp/main/.worktrees/feat-foo/task-PR-1/.worktrees" ]] || { echo "NESTED"; exit 4; }
  ) && rc=0 || rc=$?
  rm -rf "$tmp"
  case $rc in
    0) pass "F1 integration worktree created at repo-root from leaf cwd" ;;
    3) fail "F1 cwd-independence" "integration not created at repo-root" ;;
    4) fail "F1 cwd-independence" "nested integration worktree created under leaf (relative-path bug)" ;;
    *) fail "F1 cwd-independence" "unexpected rc=$rc" ;;
  esac
}

# ---------------------------------------------------------------------------
# F2: layer-1 already squash-merged into default. merge-train must skip it
#     (no replay of pre-squash commits) and rebase only the trailing unmerged
#     layer-2, exiting 0.
# ---------------------------------------------------------------------------
test_f2_skip_merged_layer() {
  local tmp rc; tmp=$(mktemp -d)
  ( make_repo "$tmp"
    cd "$tmp/main"

    # base file both layers touch.
    printf 'line1\nline2\n' > f.txt
    git_q add f.txt; git_q commit -q -m "feat: base f.txt"; git push -q origin main

    # layer-1 leaf: two intermediate commits editing f.txt.
    git_q branch feat/foo/task-PR-1 main
    git worktree add -q .worktrees/feat-foo/task-PR-1 feat/foo/task-PR-1
    ( cd .worktrees/feat-foo/task-PR-1
      printf 'line1\nline2-edit\n' > f.txt; git_q commit -aq -m "feat(l1): part a"
      printf 'line1-edit\nline2-edit\n' > f.txt; git_q commit -aq -m "feat(l1): part b" )

    # Squash-merge of layer-1 into default — a SINGLE commit whose final
    # resolution DIVERGED from the leaf's intermediate edits (the operator
    # tweaked content during squash-review). This is the realistic squash
    # hazard: replaying the leaf's part-a/part-b onto this base conflicts.
    printf 'line1-final\nline2-final\n' > f.txt
    git_q commit -aq -m "feat(l1): squashed (#1)"; git push -q origin main

    # layer-2 leaf branches from the PRE-squash layer-1 tip (real stack shape),
    # edits a DIFFERENT file so layer-2 alone never conflicts.
    git_q branch feat/foo/task-PR-2 feat/foo/task-PR-1
    git worktree add -q .worktrees/feat-foo/task-PR-2 feat/foo/task-PR-2
    ( cd .worktrees/feat-foo/task-PR-2
      echo l2 > g.txt; git_q add g.txt; git_q commit -q -m "feat(l2): add g.txt" )

    # Fake gh: PR-1 head is MERGED, PR-2 head is not. This is the
    # authoritative merged-signal merge-train uses (squash divergence makes
    # content heuristics unreliable), mirroring post-merge-cleanup.sh tests.
    mkdir -p "$tmp/bin"
    cat > "$tmp/bin/gh" <<'SHIM'
#!/usr/bin/env bash
# gh pr list --search "head:<branch>" --state merged --json number --jq ...
search=""
for ((i=1;i<=$#;i++)); do
  if [[ "${!i}" == "--search" ]]; then j=$((i+1)); search="${!j}"; fi
done
if [[ "$search" == *"feat/foo/task-PR-1"* ]]; then echo "1"; else echo ""; fi
exit 0
SHIM
    chmod +x "$tmp/bin/gh"

    # merge-train: integration built from origin/main (has divergent squashed
    # l1). Re-rebasing layer-1's part-a/part-b -> CONFLICT on f.txt. Correct
    # behavior: skip already-merged layer-1 (gh says MERGED), rebase only
    # PR-2, exit 0.
    PATH="$tmp/bin:$PATH" SD_PARALLEL_LAYERS='[["PR-1"],["PR-2"]]' \
      bash "$SCRIPT" --feature-prefix feat/foo --worktree-ns feat-foo --default-branch main >/dev/null 2>&1 \
      || { echo "RC-NONZERO"; exit 5; }

    local INT="$tmp/main/.worktrees/feat-foo/integration"
    git -C "$INT" cat-file -e "HEAD:g.txt" 2>/dev/null || { echo "NO-L2"; exit 6; }
    # layer-1's divergent final must be the one in integration (from default),
    # not the leaf's intermediate — i.e. layer-1 was NOT replayed.
    [[ "$(git -C "$INT" show HEAD:f.txt)" == $'line1-final\nline2-final' ]] || { echo "L1-REPLAYED"; exit 7; }
  ) && rc=0 || rc=$?
  rm -rf "$tmp"
  case $rc in
    0) pass "F2 already-merged layer-1 skipped, layer-2 rebased, exit 0" ;;
    5) fail "F2 skip-merged-layer" "merge-train exited non-zero (re-rebased merged layer-1 -> conflict)" ;;
    6) fail "F2 skip-merged-layer" "layer-2 content (g.txt) missing from integration HEAD" ;;
    7) fail "F2 skip-merged-layer" "layer-1 replayed onto integration (leaf intermediate, not squashed final)" ;;
    *) fail "F2 skip-merged-layer" "unexpected rc=$rc" ;;
  esac
}

echo "=== merge-train cwd-independence + skip-merged-layer ==="
test_f1_cwd_independence
test_f2_skip_merged_layer
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
