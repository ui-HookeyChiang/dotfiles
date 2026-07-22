# Stacked-merge cascade failure — incident narrative

## Why the HARD GATE exists

Symptoms observed in production 2026-05-21 — `feat/spec-advisory-fixer/task-1..5` cascade failure:

- The first PR merges cleanly. Its branch is deleted if **either** (a) you pass `--delete-branch` to `gh pr merge`, **or** (b) the repo has `delete_branch_on_merge: true` in its settings (verify with `gh api repos/<owner>/<repo> --jq .delete_branch_on_merge`). For `ubiquiti/prompt-hub` this setting is currently `false` — so `--delete-branch` is the only trigger here; on a repo with the setting enabled the cascade fires regardless of the flag.
- Every PR whose `base` pointed to the just-merged branch **auto-closes** (state=CLOSED with `mergedAt=null`). They cannot be reopened (the base branch is gone).
- The remaining PRs still in the stack become `mergeable=CONFLICTING` against main, because their branches still contain the **original commit hashes** of the now-squashed work, while main has a different commit hash representing the same content. Git sees same-content/different-hash as a 3-way merge conflict on every touched line.
- Recovery cost: ~3 hours per 5-PR stack to cherry-pick onto main, force-push, retarget base, supersede closed PRs with new ones. Plus inevitable rebase conflicts when a stale stacked branch carries the original commit hashes of work that main already has as a single squash commit.
