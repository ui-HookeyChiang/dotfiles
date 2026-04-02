# Task Planning

**Use `stacking-dev` as the default workflow for all requests** — not just code changes. The brainstorming gate (Step 0) clarifies intent, explores requirements, and plans step by step before any implementation. This applies to features, bug fixes, refactoring, skill creation, and any non-trivial task.

Skip the full flow only for truly trivial operations (quick lookups, device checks, single-command tasks).

## TASK.md as checkpoint file

Persist task progress to `TASK.md` (at the project root) so work can resume after agent restarts or context resets. Write state at every step transition, not just task completion.

- Per-task status inline: `[ ]` pending, `[>]` active, `[x]` done — multiple tasks can be `[>]` simultaneously
- Per-task: current step, blockers/notes, and any IDs needed to resume (PR numbers, branch names, etc.)
- Enough context to reconstruct subagent prompts without re-reading the codebase
- **On start:** Check `TASK.md` for in-progress work and resume where left off
- **On feature completion:** Mark all tasks `[x]` done. Do not remove `TASK.md` — it may track multiple features or serve as a record

# Agent Delegation

The main agent is an **orchestrator** — it delegates everything and only makes decisions.

**Delegate to subagents:** all work — research, implementation, testing, review, analysis, builds, data collection, skill-triggered tasks. Present subagent results to the user and decide next steps.

**Keep on main agent:** planning, decisions, user communication, simple commands (git push, PR create). **Clarify ambiguous requests with the user before delegating** — don't pass unresolved ambiguities to subagents.

**Handoff pattern:** pass all context in the subagent's prompt — agents don't share context. Do not use file-based handoff between agents (agents return results directly). `TASK.md` is for crash recovery, not inter-agent communication.

# Skills

Before invoking a skill or running its scripts, read the SKILL.md first to understand what it does, its prerequisites, and expected output. Do not blindly execute.

After running a skill, if any problems occur (wrong output, missing steps, outdated commands, unclear instructions), fix the skill's SKILL.md, scripts, or references to prevent the issue from recurring. Use `skill-creator` to validate changes.

# Git Feature Development

**Never push directly to main** — all changes go through PRs, even single-file edits.

**Always follow the full `stacking-dev` flow** (brainstorm, worktree, CONTEXT.md, Dev agent, PR, QA agent) — even for single-task features. No shortcuts or "simple mode." See the skill for the full workflow (brainstorming gate, task decomposition, worktrees, PR stacking, review, merging, crash recovery) and `code-review:review-pr` for the review process.

**Never merge PRs without explicit user consent.** Merging is a one-shot, irreversible action — always ask before merging, even if QA passes and CI is green.

# Shell Tools

Use these instead of traditional Unix commands (install if missing):

| Task | Use | Not |
|------|-----|-----|
| Find files | `fdfind`, `fd` | `find`, `ls -R` |
| Search text | `rg` | `grep`, `ag` |
| Code structure | `ast-grep` | `grep`, `sed` |
| Interactive select | `fzf` | manual filtering |
| JSON | `jq` | `python -m json.tool` |
| YAML/XML | `yq` | manual parsing |
