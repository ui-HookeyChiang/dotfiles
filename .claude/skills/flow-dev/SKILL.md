---
name: flow-dev
description: "Dev executor for per-task implementation — receives decomposed tasks from the flow orchestrator, runs the dev loop (implement + self-test in isolated worktree), pushes stacked PRs, and drives red-replay + code-review fan-in. Use for all code changes dispatched by flow. Do NOT invoke directly for converge/spec/decompose (flow owns those) or merge (flow-merge owns that)."
argument-hint: "<feature-description>"
test-devices: local
landing-group: workflow
---

# Stacked Feature Development

Dev executor backend — receives decomposed task list from `flow` orchestrator. Per-task: Dev agent → red-replay + code-review loop. Post-dev: integration test via `flow` Stage 6.

## Overview

```
main <- task-1/branch <- task-2/branch <- task-3/branch
         PR #1              PR #2             PR #3
       (base: main)    (base: task-1)    (base: task-2)
```

Each task:
1. **Dev agent** — implement + self-test in isolated worktree
2. **PR** — push and create stacked PR
3. **red-replay** — independent red→green re-run (parallel with code-review)
4. **code-review** — diff review via `code-review` skill
5. **Fix** — address feedback, resolve conversations, loop

All tasks done → **integration test** on final worktree.

> **Ubiquiti repos:** `ubiquiti-flow` adds CI polling, multi-repo, and device deployment.

## Entry Point

flow-dev receives a task list (already decomposed by `flow` orchestrator). Required inputs:

- **Task list** — each task with description, test plan, and issue path (`docs/ticket/<slug>.md`)
- **Feature prefix** — branch naming root (e.g., `feat/short-name`)
- **Default branch** — merge target (detected or provided)

Preflight (flock, gh auth, origin) is guaranteed by hooks before dispatch.

## Per-Task Dev Loop

> **Main agent stays in `$PROJECT_ROOT`.** All worktree operations use `(cd "$DIR" && ...)` or `git -C "$DIR" ...`. Never persist cwd inside a worktree.

Each task: Dev agent + two independent fan-in checks. Context via `docs/ticket/<slug>.md` in each worktree.

### Step 1: Detect defaults (once, before first task)

```bash
FEATURE_PREFIX="feat/short-feature-name"
DEFAULT_BRANCH="${SD_DEFAULT_BRANCH:-$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')}"
WORKTREE_NS="${SD_WORKTREE_NS:-${FEATURE_PREFIX#feat/}}"
```

### Step 2: Create worktree + issue context

**BASE_BRANCH dual-mode**: linear (N-1 chain) vs parallel (prior-layer first group). Rationale: `references/parallel-stacks.md`.

```bash
eval "$(bash scripts/create-task-worktree.sh "$FEATURE_PREFIX" "$N" "$DEFAULT_BRANCH" "$WORKTREE_NS")"
```

The script resolves `BASE_BRANCH` (linear vs parallel from `.flow-dev-lock`), creates the worktree, and outputs `WORKTREE_DIR`, `TASK_BRANCH`, `BASE_BRANCH` as eval-able assignments. STOP-SAFEs on lock corruption or missing GROUP_ID.

Hand off spec draft from main → worktree (copy → verify → remove → git add). No-op if no untracked specs.

**Copy the task's issue file** (`docs/ticket/<slug>.md`) into the worktree so agents can read it directly.

**Update task status:** `TaskUpdate({ taskId: "<N>", status: "in_progress" })`

Dispatched subagents are path-guarded to their assigned worktree by `guard-agent-worktree.sh`; a deny reason names the worktree path so the agent can self-correct.

### Step 3: Dev agent (implement + self-test)

Single agent: implement + test, loops until pass. Called again if feedback found.

Prompt: **[references/dev-agent-prompt.md](references/dev-agent-prompt.md)**.

### Step 4: Push and create PR

```bash
(cd "$WORKTREE_DIR" && git push origin HEAD:refs/heads/$TASK_BRANCH)
```

Create PR — body template: **[references/pr-body-template.md](references/pr-body-template.md)**.

`TaskUpdate({ taskId: "<N>", metadata: { pr: "<PR_NUMBER>" } })`

> **Merge contract.** This PR is part of a stack: merge via `Skill flow-merge`, **not** `gh pr merge --delete-branch`.

### Step 5: Independent fan-in checks

Parallel: **red-replay** + **code-review** (neither shares Dev agent state).

Prompts: **[references/red-replay-prompt.md](references/red-replay-prompt.md)**.

**Both clean** → done, next task. **Issues** → Step 3 fix loop:
  1. Dev fixes + tests
  2. Push
  3. Resolve conversations via `gh api graphql`
  4. N+1 in-flight → rebase before push
  5. 3+ attempts fail → question approach

Append `## Review results` to PR. Mark `completed`.

## Parallel Work Rules

| Task N is at... | Can start task N+1? | Constraint |
|-----------------|---------------------|------------|
| Step 5 (checks in background) | Yes — Steps 2-3 | Task N's branch must be pushed |
| Step 3 (fixing feedback) | Yes — if N+1 hasn't pushed yet | N+1 must rebase before Step 4 if N pushed new commits |
| Step 4 (PR not yet created) | No | N+1's base branch doesn't exist on remote yet |
| Same layer, any state | Yes | Both base on same prior-layer branch; Jaccard < 0.5 |

**Rebase rule:** if task N pushes new commits while N+1 is in-flight, N+1 must rebase before pushing:
```bash
(cd ".worktrees/${WORKTREE_NS}/task-$((N+1))" && git fetch origin && git rebase "origin/${FEATURE_PREFIX}/task-${N}")
```

### Layer advancement gate (parallel mode, Amendment A5)

Before opening any worktree for layer L+1, verify all groups in layer L are `completed`. Pseudocode: `references/parallel-stacks.md` § *A5 advancement gate pseudocode*.

## Feature Integration

Validate assembled feature. Full procedure: **[references/integration-protocol.md](references/integration-protocol.md)**.

1. **Merge-train** (parallel): `bash _shared/stack/merge-train.sh ...`
2. **Write integration tests** in integration/final worktree
3. **Run integration agent** — tests + full suite
4. **Update final PR** with results

## Crash Recovery

Reconstruct from `git worktree list` + `gh pr list` + `TaskList`: **[references/crash-recovery.md](references/crash-recovery.md)**.
