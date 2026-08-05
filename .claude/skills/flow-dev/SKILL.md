---
name: flow-dev
description: "Dev executor for per-task implementation — runs the dev loop (implement + self-test in isolated worktree), pushes stacked PRs, and drives red-replay + code-review fan-in. Input contract: grounded task(s). Two entries — a task list decomposed by the flow orchestrator, or direct entry with a single grounded task (bug+repro, clear scope, agent-ready ticket; self-generates the one-task list). NOT for specs (a spec skips converge but still needs decompose — flow owns that), NOT for ungrounded work (fuzzy intent goes to flow converge; bug without repro goes to diagnosing-bugs first), NOT for merge (flow-merge owns that)."
argument-hint: "<feature-description>"
test-devices: local
landing-group: workflow
---

# Stacked Feature Development

Dev executor backend — takes grounded tasks (from `flow` orchestrator, or direct entry). Per-task: Dev agent → red-replay + code-review loop. Post-dev: integration test via `flow` Stage 6.

## Overview

```
main <- task-1/branch <- task-2/branch <- task-3/branch
         PR #1              PR #2             PR #3
       (base: main)    (base: task-1)    (base: task-2)
```

Each task (step numbers match the Per-Task Dev Loop headings below):
- **Step 3 — Dev agent** — implement + self-test in isolated worktree
- **Step 3b — Mark done** — flip + move the ticket to `done/` (last PR of the stack only)
- **Step 4 — PR** — push and create stacked PR
- **Step 5 — red-replay** — independent red→green re-run (parallel with code-review)
- **Step 5 — code-review** — diff review via `code-review` skill
- **Fix loop — back to Step 3** — address feedback, resolve conversations

All tasks done → **integration test** on final worktree.

> **Ubiquiti repos:** `ubiquiti-flow` adds CI polling, multi-repo, and device deployment.

## Entry Point

Input contract: **grounded task(s)** — acceptance criterion already exists. Two entries:

- **Orchestrated** — task list already decomposed by the `flow` orchestrator.
- **Direct (single grounded task)** — bug+repro, clear scope, or an agent-ready
  ticket: self-generate the one-task list (description, test plan, issue
  path; create `docs/ticket/<slug>.md` if absent), then run the same per-task
  loop. Full flow ceremony is skipped — a single grounded task has nothing to
  converge or decompose.
- **Not direct entry**: a spec → `flow` (skips converge, still needs
  decompose into tasks). Ungrounded input bounces: fuzzy intent → `flow`
  (converge); bug without repro → `diagnosing-bugs` (produce the repro, then
  re-enter here).

Required inputs:

Handoff contract: `references/handoff-contract.json`. Validate orchestrated handoffs with `scripts/validate-handoff-contract.sh <handoff.json>` before creating task worktrees. Direct single-ticket entry may synthesize the same shape in-memory, but completion reports still use the contract output fields.

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
eval "$(bash scripts/create-task-worktree.sh "$FEATURE_PREFIX" "$N" "$DEFAULT_BRANCH" "$WORKTREE_NS" "$TICKET_PATH")"
```

The script resolves `BASE_BRANCH` (linear vs parallel from `.flow-dev-lock`), creates the worktree, and outputs `WORKTREE_DIR`, `TASK_BRANCH`, `BASE_BRANCH` as eval-able assignments. Lock reads/writes, base resolution, parent-gate checks, and status updates live behind `scripts/lock.sh`; `create-task-worktree.sh` and `update-task-status.sh` are adapters. STOP-SAFEs on lock corruption, missing GROUP_ID, blocked dependencies, or base branch not present on origin (unpushed local branch).

Hand off spec draft from main → worktree (copy → verify → remove → git add). No-op if no untracked specs.

**Copy the task's issue file** (`docs/ticket/<slug>.md`) into the worktree so agents can read it directly.

**Update task status:** `TaskUpdate({ taskId: "<N>", status: "in_progress" })`

Dispatched subagents are path-guarded to their assigned worktree by `guard-agent-worktree.sh`; a deny reason names the worktree path so the agent can self-correct.

### Step 3: Dev agent (implement + self-test)

Single agent: implement + test, loops until pass. Called again if feedback found.

Before implementation, the Dev agent MUST load `coding-guidelines` and apply the relevant guardrails to the task. For trivial tasks, keep the skill's judgment clause: loading the guardrails is mandatory; ritualizing cheap work is not.

Prompt: **[references/dev-agent-prompt.md](references/dev-agent-prompt.md)**.

### Step 3b: Mark the ticket done (before push)

After the implementation commit and before pushing, add a **standalone** commit
that closes the ticket, so the flip rides the reviewed PR diff and merging is
atomic:

```bash
(cd "$WORKTREE_DIR" \
  && python3 -c 'import re,sys,pathlib; p=pathlib.Path(sys.argv[1]); p.write_text(re.sub(r"^Status:.*$", "Status: done", p.read_text(), count=1, flags=re.M))' "docs/ticket/${SLUG}.md" \
  && mkdir -p docs/ticket/done \
  && git mv "docs/ticket/${SLUG}.md" "docs/ticket/done/${SLUG}.md" \
  && git commit -am "docs(ticket): mark ${SLUG} done")
```

Both halves — `Status: done` and the `git mv` into `docs/ticket/done/` — must land
in that one commit. `docs/agents/triage-labels.md` requires the move; flow-merge's
`verify-ticket-done` pre-merge event fails the merge if either half is missing.

**One ticket spanning several tasks/PRs flips only in the last PR of the stack.**
Earlier PRs leave the ticket untouched; a mid-stack flip would claim work the
stack has not finished.

### Step 4: Push and create PR

```bash
(cd "$WORKTREE_DIR" && git push origin HEAD:refs/heads/$TASK_BRANCH)
```

Create PR — body template: **[references/pr-body-template.md](references/pr-body-template.md)**.

`TaskUpdate({ taskId: "<N>", metadata: { pr: "<PR_NUMBER>" } })`

> **Merge contract.** This PR is part of a stack: merge via `Skill flow-merge` only. Full HARD GATE (including the `delete_branch_on_merge:true` repo-setting trigger, not just the `--delete-branch` flag): `flow-merge/references/stacked-merge-cascade.md`.

### Step 5: Independent fan-in checks

**Diff-type gate (runs first).** Classify the task's whole diff, not per-file:

| Diff shape | Fan-in |
|---|---|
| Skill-only — every changed path matches `*/SKILL.md`, `*/references/`, `*/evals/` | Skip red-replay + code-review. Equivalent legs: `make check` green + skill-writer TEST verdict (verify-skill). Append `## Review results` to the PR with the skip reason as body: `Fan-in skipped (skill-only diff) — equivalent legs: make check <result>, skill-writer TEST <verdict>`. Mark `completed`. (Same heading crash-recovery checks for the full-fan-in path below — keeps [references/crash-recovery.md](references/crash-recovery.md) detection unchanged.) |
| Touches `scripts/` or any non-skill code, **including mixed diffs** (skill prose + scripts/code in the same task) | Current fan-in below, unchanged, on the whole task. |

Mixed diffs are classified conservatively as code diffs — whole-task, not path-filtered — even though only part of the diff is code.

Parallel: **red-replay** + **code-review** (neither shares Dev agent state).
code-review internally runs multiple parallel review agents across
dimensions (n≥2) — its findings go through an independent Moderator (fresh
agent, per adversarial-review §3-5): disposition table (accept/dismiss +
reason per finding), HIGH findings cannot be dismissed (downgrade with
evidence or fix the code), gen receives Moderator output and commits fixes,
re-run if findings were HIGH.

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

### Parent-gate enforcement (Amendment A5)

`create-task-worktree.sh` parses each ticket's `Blocked by:` edges, writes them into `.flow-dev-lock` `.tasks[]`, and STOP-SAFEs if any blocker's status ≠ `completed`. Per-task status is updated via `update-task-status.sh`. This supersedes the coarse layer barrier — dependencies are now per-ticket, not per-layer.

## Feature Integration

Validate assembled feature. Full procedure: **[references/integration-protocol.md](references/integration-protocol.md)**.

1. **Merge-train** (parallel): `bash _shared/stack/merge-train.sh ...`
2. **Write integration tests** in integration/final worktree
3. **Run integration agent** — tests + full suite
4. **Update final PR** with results

## Crash Recovery

Reconstruct from `git worktree list` + `gh pr list` + `TaskList`: **[references/crash-recovery.md](references/crash-recovery.md)**.
