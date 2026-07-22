#!/bin/bash
# merge-train-absent-merged-leaf/test.sh
#
# Finding #4 (run-002 META-dogfood): re-running the FIXED merge-train end-to-end
# surfaced an edge in the F2 fix itself (fixed in commit 34494ab).
#
# By Phase 3, post-merge-cleanup.sh has ALREADY deleted the already-merged
# layer-1 leaf branch (it deletes branches only after a successful merge). So
# the normal Phase-3 state is: layer-1's leaf branch does NOT exist locally.
#
#   F4 — merge_train_leaf_merged() returned 1 ("not merged") when the leaf
#        branch was absent, so the loop then ran `git rebase <absent-leaf>` and
#        died with `fatal: invalid upstream '<leaf>'`. Correct semantics:
#        branch-absent ⇒ already merged AND cleaned up ⇒ skip (return 0). AND
#        the trailing layer-2 leaf (stacked on the now-gone layer-1) must still
#        get a correct cherry-pick base — the integration trunk that already
#        holds the squashed layer-1 content — not the absent branch name.
#
# Assertions check real git/filesystem state, not log strings.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/stack/merge-train.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS [$1]"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL [$1] — $2" >&2; }

git_q() { git -c user.email=t@t -c user.name=t "$@"; }

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
# F4: layer-1 already squash-merged into default AND its leaf branch already
#     deleted by post-merge-cleanup (the normal Phase-3 state). merge-train
#     must SKIP the absent layer-1 (not `git rebase <absent-leaf>` -> invalid
#     upstream), rebase/cherry-pick only the existing layer-2 leaf, exit 0.
#     Layer-2 was branched from the PRE-squash layer-1 tip (real stack shape):
#     its history still carries layer-1's pre-squash commits, so a naive full
#     rebase would reproduce the F2 squash conflict — the correct base for
#     layer-2 is the integration trunk that holds the squashed layer-1 content.
# ---------------------------------------------------------------------------
test_f4_absent_merged_leaf() {
  local tmp rc; tmp=$(mktemp -d)
  ( make_repo "$tmp"
    cd "$tmp/main"

    # base file both layers touch (so a wrong full rebase of layer-2 history
    # would conflict on f.txt against the divergent squash).
    printf 'line1\nline2\n' > f.txt
    git_q add f.txt; git_q commit -q -m "feat: base f.txt"; git push -q origin main

    # layer-1 leaf: two intermediate commits editing f.txt.
    git_q branch feat/foo/task-PR-1 main
    git worktree add -q .worktrees/feat-foo/task-PR-1 feat/foo/task-PR-1
    ( cd .worktrees/feat-foo/task-PR-1
      printf 'line1\nline2-edit\n' > f.txt; git_q commit -aq -m "feat(l1): part a"
      printf 'line1-edit\nline2-edit\n' > f.txt; git_q commit -aq -m "feat(l1): part b" )

    # layer-2 forks from the PRE-squash layer-1 tip (the real stack shape at
    # development time) and edits a DIFFERENT file (g.txt).
    git_q branch feat/foo/task-PR-2 feat/foo/task-PR-1
    git worktree add -q .worktrees/feat-foo/task-PR-2 feat/foo/task-PR-2
    ( cd .worktrees/feat-foo/task-PR-2
      echo l2 > g.txt; git_q add g.txt; git_q commit -q -m "feat(l2): add g.txt" )

    # Squash-merge of layer-1 into default — divergent final resolution (the
    # realistic squash hazard). origin/main now holds the squashed layer-1.
    printf 'line1-final\nline2-final\n' > f.txt
    git_q commit -aq -m "feat(l1): squashed (#1)"; git push -q origin main

    # A5 advancement gate: after layer-1 merged, layer-2's leaf is rebased onto
    # the NEW default (drops layer-1's now-squashed pre-squash commits) BEFORE
    # layer-1's branch is cleaned up. This is the real Phase-3 ordering — by the
    # time layer-1's branch is gone, layer-2 carries only its OWN commit.
    ( cd .worktrees/feat-foo/task-PR-2
      git_q rebase --onto main feat/foo/task-PR-1 feat/foo/task-PR-2 >/dev/null 2>&1 )

    # post-merge-cleanup ALREADY removed layer-1's worktree + branch (it deletes
    # branches only after a successful merge). Simulate the normal Phase-3 state.
    git worktree remove --force .worktrees/feat-foo/task-PR-1
    git_q branch -D feat/foo/task-PR-1
    # Sanity: layer-1 branch is truly absent now.
    if git rev-parse --verify feat/foo/task-PR-1 >/dev/null 2>&1; then
      echo "FIXTURE-BAD"; exit 9
    fi

    # Use the offline ancestry path (SD_SKIP_REMOTE=1): for an ABSENT branch the
    # merged-detection cannot resolve it anyway — branch-absent must be treated
    # as merged regardless of remote signal.
    SD_SKIP_REMOTE=1 SD_PARALLEL_LAYERS='[["PR-1"],["PR-2"]]' \
      bash "$SCRIPT" --feature-prefix feat/foo --worktree-ns feat-foo --default-branch main >/dev/null 2>&1 \
      || { echo "RC-NONZERO"; exit 5; }

    local INT="$tmp/main/.worktrees/feat-foo/integration"
    # layer-2's unique file must be present.
    git -C "$INT" cat-file -e "HEAD:g.txt" 2>/dev/null || { echo "NO-L2"; exit 6; }
    # layer-1's divergent squashed final must be the f.txt in integration (came
    # from default); layer-1 must NOT have been replayed.
    [[ "$(git -C "$INT" show HEAD:f.txt)" == $'line1-final\nline2-final' ]] || { echo "L1-REPLAYED"; exit 7; }
  ) && rc=0 || rc=$?
  rm -rf "$tmp"
  case $rc in
    0) pass "F4 absent merged layer-1 skipped, layer-2 cherry-picked onto trunk, exit 0" ;;
    5) fail "F4 absent-merged-leaf" "merge-train exited non-zero (rebased absent leaf -> invalid upstream, or replayed conflict)" ;;
    6) fail "F4 absent-merged-leaf" "layer-2 content (g.txt) missing from integration HEAD" ;;
    7) fail "F4 absent-merged-leaf" "layer-1 replayed onto integration (leaf intermediate, not squashed final)" ;;
    9) fail "F4 absent-merged-leaf" "fixture setup: layer-1 branch was not actually deleted" ;;
    *) fail "F4 absent-merged-leaf" "unexpected rc=$rc" ;;
  esac
}

echo "=== merge-train absent-merged-leaf (Finding #4) ==="
test_f4_absent_merged_leaf
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
