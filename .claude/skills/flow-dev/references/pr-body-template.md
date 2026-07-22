# Stacked PR body template (Per-Task Dev Loop, Step 4)

Use this template when running `gh pr create` for each task in a
stacked feature:

```bash
gh pr create \
  --base "$BASE_BRANCH" \
  --title "feat: task ${N} - <short description>" \
  --body "$(cat <<'EOF'
## Summary
- <what this task does>

## Part of
- Feature: <feature description>
- Task ${N} of ${TOTAL_TASKS}
- Stacked on: #<previous-PR-number> (or main)

## Changes
- <list of changes>

## Test plan
- [x] <acceptance criteria 1 — checked after passing>
- [x] <acceptance criteria 2 — checked after passing>
EOF
)"
```

## Notes

- `BASE_BRANCH` is the previous task's branch (or `$DEFAULT_BRANCH` for task 1).
- After creation, store the PR number in task metadata via
  `TaskUpdate({ taskId, metadata: { pr: <num> } })`.
- For final task, also append integration test results (Feature Integration) and
  Jira ticket prefix to the PR title/body via
  `gh api repos/{owner}/{repo}/pulls/$PR_NUM -X PATCH`.
