# Rules

## Workflow routing

For code changes, invoke `stack` (it handles spec creation if missing) — it sizes the work and routes all changes, including small single-file fixes, through the full pipeline (grill-with-docs → to-prd → to-issues → stack-dev → stack-merge).
For non-code work (questions, debug, config, deploy, perspective audits), use the matching domain skill — not stack.
superpowers skills are subordinate — used within stack's phases, not directly.
Always delegate execution to subagents.

## Safety

**Never push directly to main** — all changes go through PRs.

**Release exception:** `semver-release` may push directly to main, but ONLY commits limited to `debian/changelog`, `releases/`, and version tags (`v*`). Any release that also needs code changes: those land via PR first, then `semver-release` tags the merged result.

**Never merge PRs without explicit user consent.**

# Delegation

The main agent orchestrates and handles single-file changes directly (session model). Everything else — multi-file changes, code review, exploration — delegates to a subagent on `claude-sonnet-4-6`.

# Language

Reply to the user in **Traditional Chinese (繁體中文)** rather than Simplified Chinese. Keep technical terms, code symbols, command names, file paths, and library names in English (e.g. don't translate `git rebase`, `setMyCommands`, `SessionManager`).

@RTK.md
@memory-discipline.md
@sandbox-protected-paths.md
@shell-tools.md
