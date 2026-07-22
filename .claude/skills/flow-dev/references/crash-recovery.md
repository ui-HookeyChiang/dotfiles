# Crash Recovery

On restart, reconstruct feature state from git and GitHub — there is no task tracker file to read.

## Recovery steps

1. **Discover feature state** from git:
   ```bash
   git worktree list                    # find active worktrees
   gh pr list --author @me --state open --json number,title,headRefName,baseRefName
   git branch -r | grep "feat/"        # find feature branches
   ```

2. **Find the design spec** — look in `docs/superpowers/specs/` for `<date>-<slug>-design.md`. The spec contains feature context and decisions.

3. **If resuming the same Claude Code session**, `TaskList` still has the full task state. Check it first before reconstructing.

4. **For a new session**, reconstruct tasks from git/PR state:
   - Each worktree or open PR = one task
   - PR with "Review results" in description = task completed
   - PR without "Review results" = task needs red-replay + code-review (Step 5) or is in progress
   - No PR but worktree exists = task needs push + PR (Step 4)
   - No worktree and no PR = task not started yet

   Re-create tasks with `TaskCreate`, set status with `TaskUpdate`:
   ```
   TaskCreate({ subject: "Task N: <from PR title>", description: "<from PR body>" })
   TaskUpdate({ taskId: "<N>", status: "completed", metadata: { pr: "<PR#>" } })  // for done tasks
   TaskUpdate({ taskId: "<N>", status: "in_progress", metadata: { pr: "<PR#>" } })  // for active tasks
   ```

5. **Resume each active task** from its next step:
   - Worktree exists, no commits beyond base → Step 3 (dev agent)
   - Commits exist, not pushed → Step 4 (push + PR)
   - PR exists, no "Review results" → Step 5 (red-replay agent + code-review step)
   - red-replay / review found issues → Step 3 with the findings
   - both checks passed → mark completed, move to next task

6. Handle the **earliest unfinished task first** — it may unblock later ones via rebase

7. All steps are idempotent or can be re-run safely — when in doubt, re-run the current step

## If worktrees are missing

```bash
# Recreate worktree from existing remote branch
git worktree add ".worktrees/${WORKTREE_NS}/task-${N}" "origin/${FEATURE_PREFIX}/task-${N}"
```

## Feature Integration recovery

If all dev tasks had PRs but integration tests weren't run:
1. Recreate the integration test task: `TaskCreate` with the test plan. If the integration test plan is not available (task descriptions are ephemeral across sessions), re-derive it from the design spec (`docs/superpowers/specs/`) and the implemented code.
2. Check the final task's worktree for existing integration test code
3. If test code exists, run it. If not, write it from the plan, then run.
