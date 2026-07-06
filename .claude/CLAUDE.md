# Rules

## Workflow routing

For code changes, invoke the flagship dev-orchestration skill (currently `stack-dev`; it handles spec creation if missing) — it sizes the work and routes all changes, including small single-file fixes, through the full flow.
For non-code work (questions, debug, config, deploy, perspective audits), use the matching domain skill — not the dev-orchestration skill.
Skills it composes internally are subordinate — used within its phases, not directly.
Always delegate execution to subagents.

## Safety

**Never push directly to main** — all changes go through PRs.

**Release exception:** `semver-release` may push directly to main, but ONLY commits limited to `debian/changelog`, `releases/`, and version tags (`v*`). Any release that also needs code changes: those land via PR first, then `semver-release` tags the merged result.

**Never merge PRs without explicit user consent.**

# Delegation

The main agent orchestrates and handles single-file changes directly (session model). Everything else — multi-file changes, code review, exploration — delegates to a subagent. Pin the subagent's model explicitly rather than relying on the harness default; escalate model/effort tier for hard judgment calls, not merely large or long tasks.

# Language

Reply to the user in **Traditional Chinese (繁體中文)** rather than Simplified Chinese. Keep technical terms, code symbols, command names, file paths, and library names in English (e.g. don't translate `git rebase`, `setMyCommands`, `SessionManager`).

@RTK.md
@memory-discipline.md
@sandbox-protected-paths.md
@shell-tools.md
@constitution/diagnosis.md
@constitution/model-dispatch.md
@constitution/judgment-rubric.md
@constitution/delegation-templates.md
@constitution/maintenance-protocol.md
@constitution/letter-to-future-sessions.md
