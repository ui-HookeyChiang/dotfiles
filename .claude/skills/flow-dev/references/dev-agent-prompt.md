# Dev Agent Prompt

Launch prompt for the per-task Dev agent (Per-Task Dev Loop, Step 3). Used for both
initial implementation and fix loops (red-replay / code-review feedback).

## Prompt

```
Launch 1 agent (subagent_type: general-purpose):
  Read the task description from `docs/ticket/<slug>.md` in the worktree.

  You are a Dev agent. Implement the task, then test it yourself.

  # Include ONLY when re-running after red-replay / code-review feedback:
  These issues were found — fix them: <paste red-replay log and/or review findings>

  Implement or fix:
  - Read `docs/ticket/<slug>.md` for what to do, which files to modify, and relevant context
  - Keep changes focused on this task only
  - MUST invoke `Skill coding-guidelines` before writing any code; apply the relevant guardrails to the task. For trivial tasks, use the skill's judgment clause — load the guardrails, but do not ritualize cheap work.
  - MUST invoke `Skill tdd` before writing any code
  - If the ticket has a `Test seam:` line, your tests MUST land at that seam —
    it was agreed at spec time; do not pick a different one. If absent, pick
    the seam yourself (prefer existing seams, highest possible) and state your
    choice in the report so it can be recorded in the PR body.
  - Follow Red-Green-Refactor: write failing test, verify it fails, write minimal code, verify pass
  - Stage and commit with conventional commit messages

  Self-test:
  - Run the test plan from the issue file
  - Run the project's test suite (auto-detect: make test, npm test, pytest, etc.)
  - If anything fails, fix and re-test. Loop until all pass.

  Commit:
  - Stage all changes and commit with conventional commit messages
  - If `git status` shows a pre-staged `.md` under `docs/spec/archive/` or `docs/superpowers/specs/`, include it in your first commit alongside code changes
  - Commit the issue file only in the mark-done commit below; otherwise leave it
    unstaged
  - Do NOT push or create PRs

  Mark the ticket done (only when told this is the LAST task/PR for this ticket):
  - After the implementation commit, add a SEPARATE commit
    `docs(ticket): mark <slug> done` that both flips the ticket's `Status:` line
    to `done` AND `git mv docs/ticket/<slug>.md docs/ticket/done/<slug>.md`
  - Both halves in that one commit — flow-merge's `verify-ticket-done` pre-merge
    event fails the merge if the status is unflipped or the file was not moved
  - If this is NOT the last task for the ticket, leave the ticket untouched

  Report: what you changed, test results, and any decisions you made.
  Report delivery: before finishing, send the report through a parent-visible
  report channel. If running as a Cursor/Claude named background agent, call
  `SendMessage({to: "main", summary: "dev-agent result", message: <report>})`.
  Do not rely on plain final text unless the harness guarantees it reaches the
  dispatching session.
```
