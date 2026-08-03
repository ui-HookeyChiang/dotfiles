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
order, then runs registered merge events.

## Merge Event Contract

flow-merge owns merge ordering, verification, cleanup, and the event loop.
Callers inject event names; they do not wrap merge mechanics.

Hook slots:

- `pre_merge`: runs before each merge operation. Use for gates such as
  `validate-git-status`, or metadata-only updates such as `pr-metadata-sync`.
- `post_merge`: runs after the whole stack shows `MERGED`. Use for cleanup,
  ticket status, release, or domain events.

Generic registry: `references/merge-events.tsv`.

Schema:

```tsv
name    phase    implementation    needs    gate
```

- `implementation`: `script:<path>` or `skill:<skill-name>`.
- `needs`: comma-separated event names that must have status `ran`.
- `gate`: `none` or `user`. User-gated events must be confirmed up front,
  before the first merge starts.
- `skill:<name>`: dispatches a sibling skill through
  `FLOW_MERGE_SKILL_DISPATCHER=<command>`. The runner invokes it as
  `<command> <skill-name>`. Without a dispatcher, skill events fail closed and
  are not marked `ran`.

Event semantics:

- Unknown event, wrong phase, failed implementation, or unsatisfied user gate
  records `failed`.
- Event whose dependency did not `ran` records `skipped-due-to-needs`.
- In `post_merge`, terminal status events (`ticket-done` by default) are skipped
  after any earlier post-merge failure.
- Independent events continue after a failure.
- Any `failed` or `skipped-due-to-needs` outcome makes the run red; do not mark
  tickets done until the report is clean.

## Procedure

### 0. Confirm user-gated events

Before any merge mutation, list and confirm enabled `gate: user` events once:

```bash
POST_MERGE_EVENTS="${POST_MERGE_EVENTS:-cleanup,ticket-done}"
bash flow-merge/scripts/run-merge-events.sh \
  --phase post_merge \
  --events "$POST_MERGE_EVENTS" \
  --confirm-user-gates-only \
  --report "${TMPDIR:-/tmp}/flow-merge-user-gates.tsv"
export FLOW_MERGE_USER_GATES_CONFIRMED=1
```

The runner exports `FLOW_MERGE_USER_GATES_CONFIRMED=1` after this confirmation.
`semver-release` and `release-publish` treat that env as the answer to their
`[y/N]` prompt for this merge run only. Do not bypass their other guards:
changelog/tag checks, path-scope checks, review requirements, credential checks,
and dry-run behavior still apply inside those skills.

### 1. Pre-merge gate

Verify the stack is mergeable:

- Every PR approved, CI green, no unresolved review threads.
- If conflicts exist → invoke `Skill resolving-merge-conflicts`, then
  re-enter this step.

Run configured `pre_merge` events:

```bash
bash flow-merge/scripts/run-merge-events.sh \
  --phase pre_merge \
  --events "${PRE_MERGE_EVENTS:-validate-git-status}" \
  --report "${TMPDIR:-/tmp}/flow-merge-pre-events.tsv"
```

To finalize the squash-merge title/body without changing the branch, inject
`pr-metadata-sync` before the merge and pass the target PR metadata:

```bash
FLOW_MERGE_PR="${PR_NUMBER}" \
FLOW_MERGE_PR_TITLE="${PR_TITLE}" \
FLOW_MERGE_PR_BODY_FILE="${PR_BODY_FILE}" \
bash flow-merge/scripts/run-merge-events.sh \
  --phase pre_merge \
  --events pr-metadata-sync,validate-git-status \
  --report "${TMPDIR:-/tmp}/flow-merge-pre-events.tsv"
```

Use `FLOW_MERGE_REPO=owner/repo` when the current checkout is not the PR's
GitHub repository.

**Completion:** every PR shows `MERGEABLE` in `gh pr view --json mergeable`.

### 2. Cascade merge

Single PR (not a stack): run the merge from a neutral directory with `--repo`.
This prevents `gh` from trying to switch the local checkout back to `main`,
which fails when `main` is already checked out in another worktree.

```bash
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
(cd "${TMPDIR:-/tmp}" && gh pr merge "$PR_NUMBER" \
  --repo "$REPO" \
  --squash \
  --delete-branch)
```

Stacked PR series:

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

### 3. Post-merge events

If `POST_MERGE_EVENTS` includes any `skill:<name>` registry event, set
`FLOW_MERGE_SKILL_DISPATCHER` before running the event loop.

```bash
FLOW_MERGE_CLEANUP_MODE=stack \
FLOW_MERGE_FEATURE_PREFIX="${FEATURE_PREFIX}" \
FLOW_MERGE_TOTAL_TASKS="${TOTAL_TASKS}" \
FLOW_MERGE_DEFAULT_BRANCH="${DEFAULT_BRANCH}" \
bash flow-merge/scripts/run-merge-events.sh \
  --phase post_merge \
  --events "${POST_MERGE_EVENTS:-cleanup,ticket-done}" \
  --report .flow-merge-post-events.tsv
```

Built-in generic events:

- `cleanup`: invokes `_shared/stack/post-merge-cleanup.sh`; idempotent and safe
  to re-run on partial cleanup.
- `ticket-done`: marks supplied local ticket/spec files done only after its
  declared dependencies ran.
- `validate-git-status`: validates a clean git worktree before merge mutation.
- `pr-metadata-sync`: updates PR title/body through the GitHub API before merge
  mutation; it must not edit repository contents.
- `semver-release`: user-gated release bump/tag skill event.
- `release-publish`: user-gated publish skill event; depends on
  `semver-release`.

**Completion:** `git branch | grep ${FEATURE_PREFIX}` returns nothing.

### 4. Status updates

Status updates are merge events, not a prose-only step. Pass ticket paths via
`FLOW_MERGE_TICKETS` (colon-separated) and the optional parent spec/PRD via
`FLOW_MERGE_PRD` before running `ticket-done`.

If Jira is configured, inject the domain event from the caller's registry; do
not add a separate ad hoc post-merge step.

**Completion:** post-merge event report contains only `ran`.

To retry a fixed post-merge event without re-merging, pass the prior report so
already successful dependencies count as `ran`:

```bash
FLOW_MERGE_USER_GATES_CONFIRMED=1 \
bash flow-merge/scripts/run-merge-events.sh \
  --phase post_merge \
  --events release-publish \
  --prior-report .flow-merge-post-events.tsv \
  --report .flow-merge-post-events-rerun.tsv
```

### 5. Report

Print:
- PRs merged (number + title)
- Event report path and per-event outcomes (`ran`, `failed`,
  `skipped-due-to-needs`)
- Branches cleaned and issues marked done
- Warnings (failed events, leftover branches)
