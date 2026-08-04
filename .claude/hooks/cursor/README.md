# Cursor Hook Adapter

## cli-config.json deny list is empty

Cursor's permission grammar (`Shell(<first-token>)`) matches only the first token of a command — it cannot express argument patterns at all. This prevents expressing any deny rule for structured commands:
- `rm -rf /` — cannot match; Shell(rm) would be too broad
- `git push --force` — cannot match arguments; Shell(git) would be too broad
- `git add -A` — cannot match flags; Shell(git) would be too broad
- `gh pr edit --title` — cannot match arguments; Shell(gh) would be too broad

**Solution:** Argument-sensitive guards are enforced via `translate-hook.sh`, which bridges Claude Code hooks (which support full arg patterns) to Cursor's flatter first-token-only syntax. The `cli-config.json` deny list is empty because no rule can be expressed in Cursor's grammar.

For each Cursor hook defined in `hooks/manifest.json` (shape: `flat`), the bridge:
1. Receives Cursor-shaped JSON with command/tool info
2. Passes it to the underlying Claude Code hook script (e.g., `block-bare-read.sh`)
3. Translates the Claude Code output JSON to Cursor output shape

Hooks providing guards include:
- `block-main-edit.sh` — worktree requirement (file tool writes only in linked worktrees)
- `block-bare-read.sh` — denies bare cat/head/tail + handles shell exploration (env, command, timeout, bash -c wrappers)
- `block-heredoc-continuation.sh` — validates heredoc terminator shapes
- `guard-stale-base.sh` — ensures base branch freshness
- `guard-agent-worktree.sh` — enforces subagent worktree isolation

See `hooks/manifest.json` Cursor entries (shape: `flat`) for active bridged hooks. Arg-sensitive git/gh command guards require dedicated hooks — not currently implemented.
