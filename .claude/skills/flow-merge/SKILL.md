---
name: flow-merge
description: >-
  Cascade-merge a stacked PR series in dependency order and clean up.
  Use when PRs are approved and the user says "merge the stack",
  "squash merge", "merge and cleanup", or when another skill dispatches
  the merge phase. NOT for creating PRs (flow-dev), NOT for resolving
  conflicts (resolving-merge-conflicts).
argument-hint: "<PR-number|'stack'|branch-prefix>"
landing-group: workflow
---

# Flow Merge

Cascade executor — squash-merges a stacked PR series in leaf-to-root
order, then removes every artifact the stack left behind.

## Procedure

### 1. Pre-merge gate

Verify the stack is mergeable:

- Every PR approved, CI green, no unresolved review threads.
- If conflicts exist → invoke `Skill resolving-merge-conflicts`, then
  re-enter this step.

**Completion:** every PR shows `MERGEABLE` in `gh pr view --json mergeable`.

### 2. Cascade merge

```bash
bash _shared/stack/squash-merge.sh stack \
  "${FEATURE_PREFIX}" "${TOTAL_TASKS}" "${DEFAULT_BRANCH}"
```

The script squash-merges each PR leaf-to-root, rebasing downstream
bases after each merge. On mid-cascade conflict: invoke
`Skill resolving-merge-conflicts`, then retry the script.

> **HARD GATE** — never `gh pr merge --delete-branch` a stacked PR
> directly. The cascade rebase would break. See [references/stacked-merge-cascade.md](references/stacked-merge-cascade.md).

**Completion:** every PR in the stack shows state `MERGED`.

### 3. Cleanup

```bash
bash _shared/stack/post-merge-cleanup.sh stack \
  "${FEATURE_PREFIX}" "${TOTAL_TASKS}" "${DEFAULT_BRANCH}"
```

Removes remote branches, local branches, and worktrees. Idempotent —
safe to re-run on partial cleanup.

**Completion:** `git branch | grep ${FEATURE_PREFIX}` returns nothing.

### 4. Status updates

- Each `docs/ticket/<slug>.md` for this feature: `Status:` → `done`.
- If all issues under a PRD are done: PRD `status:` → `done`.
- If Jira configured: use `ubiquiti-jira` skill for transition.

**Completion:** no issue file for this feature still shows
`Status: ready-for-agent`.

### 5. Report

Print:
- PRs merged (number + title)
- Branches cleaned
- Issues marked done
- Warnings (failed Jira, leftover branches)
