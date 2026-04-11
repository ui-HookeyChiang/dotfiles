# Rules

Invoke `stacking-dev` for all requests. Always delegate execution to subagents.

**Never push directly to main** — all changes go through PRs.

**Never merge PRs without explicit user consent.**

# Delegation

The main agent orchestrates — it delegates and decides, never executes directly.

**Handoff:** pass context in the subagent's prompt for one-shot tasks. Use CONTEXT.md for worktree-based agents that need persistent context. Subagents return results directly — don't poll files for output.

# Shell Tools

When using Bash for tasks without a dedicated tool:

| Task | Use |
|------|-----|
| Code structure | `ast-grep` |
| JSON | `jq` |
| YAML/XML | `yq` |
| Interactive select | `fzf` |
