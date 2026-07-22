# Integration Protocol

Full procedure for feature integration after all per-task dev
loops are complete and reviewed.

## Merge-train: collapse leaves into integration worktree (parallel mode)

With `parallel_layers != null`, N file-disjoint leaves must be
reassembled before integration testing. Run from a leaf worktree
(merge-train.sh reads `.flow-dev-lock` from `$PWD`):

```bash
cd ".worktrees/${WORKTREE_NS}/task-PR-1"
bash ~/.claude/skills/_shared/stack/merge-train.sh \
  --feature-prefix "$FEATURE_PREFIX" \
  --worktree-ns "$WORKTREE_NS" \
  --default-branch "$DEFAULT_BRANCH"
```

Creates ephemeral `.worktrees/${WORKTREE_NS}/integration/` from
`origin/$DEFAULT_BRANCH`, rebases every leaf in layer order, STOP-SAFEs
on conflict. Conflict-resolution + linear-mode exit-2 fallback:
`parallel-stacks.md` § *Rebase conflicts during merge-train*
and § *merge-train linear-mode fallback*.

## Write integration test code

Integration tests live in `.worktrees/${WORKTREE_NS}/integration/`
(parallel mode) or the final task's worktree (linear mode). Implement
the integration test plan from the integration test task (retrieve via
`TaskGet`). The plan specifies *what* to test — this step writes the
*code*.

Write tests in `scripts/tests/` (or the project's existing test directory). Use
the project's test framework (pytest, jest, go test, etc.). If the project has no
test framework, write executable scripts that exit non-zero on failure. Tests must
be runnable standalone (no manual setup steps). These tests are **kept permanently**
as the project's regression suite.

If the integration test plan needs updates (e.g., interfaces changed during dev,
new edge cases discovered), update the task description with `TaskUpdate` first,
then write the code to match.

Commit the integration tests in the final task's worktree.

## Run integration tests

Launch an **integration agent** to execute the integration tests plus the full
project test suite:

```
Launch 1 agent:
  Read the task description from `docs/ticket/<slug>.md` in the integration container:
    - Parallel mode: .worktrees/${WORKTREE_NS}/integration/
    - Linear mode:   .worktrees/${WORKTREE_NS}/task-${TOTAL_TASKS}/

  You are an integration agent.
  - Run the integration tests written above
  - Run the full project test suite
  - Run the feature's integration test plan (defined in the task list or the final task)
  - Report pass/fail with full output for any failures
```

**If integration tests fail:** fix in the appropriate task's worktree, re-run that
task's test plan, push, and rebase downstream tasks:

```bash
# After fixing task N, rebase all later tasks onto updated task N
for t in $(seq $((N+1)) $TOTAL_TASKS); do
  (cd ".worktrees/${WORKTREE_NS}/task-${t}" && \
    git fetch origin && \
    git rebase "origin/${FEATURE_PREFIX}/task-$((t-1))" && \
    git push --force-with-lease origin HEAD:refs/heads/${FEATURE_PREFIX}/task-${t})
done
```

Note: this uses plain `rebase` (not `--onto`) because the branches haven't been
squash-merged yet — task-N's branch still exists with its original commits.
`--onto` is only needed after squash-merge during the final merge phase.

## Update final PR with integration test results

After all integration tests pass, append `## Integration test results` to
the final task's PR description via `gh api repos/{owner}/{repo}/pulls/$FINAL_PR_NUM -X PATCH -f body="..."`.
Include a table of test results (check + PASS/FAIL).

## Overall feature review (optional)

Optionally launch one agent to review cross-task consistency, composition, and edge
cases across all PRs. Post findings on the final task's PR.
