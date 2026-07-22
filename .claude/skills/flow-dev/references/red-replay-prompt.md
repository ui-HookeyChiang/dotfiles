# Red-Replay Agent Prompt

Launch prompt for the per-task red-replay agent (Per-Task Dev Loop, Step 5a).
Runs in background, parallel with code-review.

An independent (non-author) per-task verifier that REPLAYS the Dev agent's
red→green transition in a **scratch checkout** — does NOT reuse the Dev
agent's worktree, test logs, env vars, or temp fixtures.

## Prompt

```
Launch 1 agent (background):
  Read the task description from `docs/ticket/<slug>.md` in .worktrees/${WORKTREE_NS}/task-${N}/

  You are a red-replay agent. Independently REPLAY this task's red→green
  transition. You are NOT the test author — do not edit tests or impl.

  Work in a SCRATCH checkout (detached worktree at specific SHA):
      SCRATCH=$(mktemp -d)
      git worktree add --detach "$SCRATCH" <impl-absent-sha>

  1. impl-absent ref: re-run THIS task's own tests. Expect RED — verify it is
     a REAL right-reason failure (assertion, not setup/import error).
  2. impl ref: `git -C "$SCRATCH" checkout --detach <impl-sha>`, re-run tests.
     Expect GREEN. Then run compile/lint/type-check per file (one invocation
     each, e.g. `bash -n <file>`). Deeper linter (shellcheck, mypy) is
     best-effort.
  3. Do NOT run the full project test suite (Feature Integration owns that).

  Pass only if BOTH transition holds AND per-file syntax passes.
  On failure → report with evidence; do NOT silently pass.

  TEARDOWN: git worktree remove --force "$SCRATCH" && git worktree prune

  Report: red/green result + syntax + lint, with command output.
```

## Code-review step (5b, parallel with red-replay)

Delegates to the `code-review` skill on THIS task's diff. Unconditional — no CI gating.

```
Launch 1 agent (background):
  Read the task description from `docs/ticket/<slug>.md` in .worktrees/${WORKTREE_NS}/task-${N}/

  You are the code-review step. Review THIS task's diff (git diff <base>..HEAD).
  Invoke the `code-review` skill. If unavailable, STOP and surface.

  Report: list of review issues (if any), with severity. Be concise.
```
