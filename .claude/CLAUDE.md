# Rules

## Workflow routing

For code changes, invoke `stacking-dev` (it handles spec creation if missing) — it sizes the work and routes all changes, including small single-file fixes, through the full flow.
For non-code work (questions, debug, config, deploy, perspective audits), use the matching domain skill — not stacking-dev.
superpowers skills are subordinate — used within stacking-dev's phases, not directly.
Always delegate execution to subagents.

## Safety

**Never push directly to main** — all changes go through PRs.

**Release exception:** `semver-release` may push directly to main, but ONLY commits limited to `debian/changelog`, `releases/`, and version tags (`v*`). Any release that also needs code changes: those land via PR first, then `semver-release` tags the merged result.

**Never merge PRs without explicit user consent.**

# Delegation

The main agent orchestrates and handles single-file changes directly (session model). Everything else — multi-file changes, code review, exploration — delegates to a subagent on `claude-sonnet-4-6`.

**Handoff:** pass context in the subagent's prompt for one-shot tasks. Use HANDOFF.md for worktree-based agents that need persistent context. Subagents return results directly — don't poll files for output.

# Shell Tools

When using Bash for tasks without a dedicated tool:

| Task | Use |
|------|-----|
| Search file contents | `Grep` tool (ripgrep) or `rg` |
| Find files by name | `fdfind` (Linux) / `fd` (macOS) |
| Code structure | `ast-grep` |
| JSON | `jq` |
| YAML/XML | `yq` |
| Interactive select | `fzf` |

`grep`/`egrep`/`fgrep`/`find` are denied in settings.json (hard-blocked). Don't try `bash -c` or pipeline workarounds — use the alternatives above. Note: `fd` alias from `.zshrc` doesn't expand in Bash tool (non-interactive zsh) — call the binary directly by its OS-specific name.

# Language

Reply to the user in **Traditional Chinese (繁體中文)** rather than Simplified Chinese. Keep technical terms, code symbols, command names, file paths, and library names in English (e.g. don't translate `git rebase`, `setMyCommands`, `SessionManager`).

@RTK.md
@memory-discipline.md
@sandbox-protected-paths.md
