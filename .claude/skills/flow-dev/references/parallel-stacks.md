# Parallel stacks — operator guide

Applies when the `stack` orchestrator detects multi-group parallel layers during task decomposition.

## Activation conditions (all three required)

1. Plan adoption finds an upstream `to-tickets` plan.
2. Plan splits into ≥ 2 PR groups with pairwise Jaccard(files) < 0.5.
3. User answers `[y]` (interactive) OR `SD_PARALLEL_MODE=y` (non-interactive).

Otherwise: linear mode (no merge-train, no integration worktree).

## Parallel-mode confirmation precedence

| Priority | Condition | Result |
|---|---|---|
| 1 (highest) | `SD_PARALLEL_MODE=y` | Use raw layers, no prompt |
| 2 | stdin not TTY (`[[ ! -t 0 ]]`) | Sequential flatten (`[s]`) |
| 3 | Interactive TTY, no overrides | Prompt user (3 keys; `[n]` aborts) |

## Worktree topology

```
main
└── feat/foo/task-PR-1      (layer 1)
    ├── feat/foo/task-PR-2  (layer 2, base=task-PR-1)
    └── feat/foo/task-PR-3  (layer 2, base=task-PR-1)
        └── feat/foo/task-PR-4  (layer 3, base=task-PR-2)
```

Same-layer groups share a base (first group of prior layer). Dev agents
dispatch in parallel within a layer; advancement gate blocks until ALL
groups in the current layer pass fan-in checks.

## Merge-train

```bash
cd ".worktrees/${WORKTREE_NS}/task-PR-1"   # any leaf worktree with lock
bash ~/.claude/skills/_shared/stack/merge-train.sh \
  --feature-prefix "$FEATURE_PREFIX" \
  --worktree-ns "$WORKTREE_NS" \
  --default-branch "$DEFAULT_BRANCH"
```

Override (no lock context): `export SD_PARALLEL_LAYERS='[["PR-1"],["PR-2","PR-3"]]'`

The script creates an ephemeral integration worktree, rebases each group
in layer order. Already-merged branches are skipped; trailing unmerged
leaves cherry-pick `${predecessor}..${leaf}` instead of rebasing.

## Rebase conflicts

| Type | Action |
|---|---|
| Trivial (adjacent edits) | Resolve in `$INT_DIR`, `git rebase --continue`, re-run merge-train |
| Structural (leaves not independent) | Flatten layers: `jq '.parallel_layers = [.parallel_layers[][] \| [.]]' .flow-dev-lock \| sponge .flow-dev-lock`; restart Per-Task Dev Loop |
| Abort | `git rebase --abort` → `git worktree remove --force` → re-run rebuilds from scratch |

## Cherry-pick ordering (flow-merge)

`squash-merge.sh stack` walks `parallel_layers` in JSON-array order.
PARENT = first group of prior layer (same BASE_BRANCH logic as worktree topology above).
Linear mode: numeric 1..N, `task-(N-1)` as PARENT.

## Recovery

| Scenario | Action |
|---|---|
| Crash mid-dev-loop | `git worktree list` + lock's `parallel_layers` → resume unfinished groups |
| Integration worktree contaminated | `git rebase --abort` → `git worktree remove --force` → re-run |
| Regret `[y]` parallel choice | Flatten lock (jq command above) → next dev loop picks up sequential order |
