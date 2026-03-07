# Task Planning

**When you don't have a clear plan for the next steps, enter plan mode first.** This includes:
- Complex or ambiguous requests where the approach isn't obvious
- Tasks touching unfamiliar code or multiple systems
- Anytime you'd otherwise guess and iterate — plan instead

If the task is straightforward and you know exactly what to do, skip planning and execute directly.

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

**Keep on main agent:** planning, decisions, user communication, simple commands (git push, PR create).

**Handoff pattern:** pass all context in the subagent's prompt — agents don't share context. Do not use file-based handoff between agents (agents return results directly). `TASK.md` is for crash recovery, not inter-agent communication.

# Skills

Before invoking a skill or running its scripts, read the SKILL.md first to understand what it does, its prerequisites, and expected output. Do not blindly execute.

After running a skill, if any problems occur (wrong output, missing steps, outdated commands, unclear instructions), fix the skill's SKILL.md, scripts, or references to prevent the issue from recurring. Use `skill-creator` to validate changes.

# Git Feature Development

When developing features under git, use **stacked PRs** as the default workflow. See the `stacking-feature-dev` skill for the full workflow (task decomposition, worktrees, PR stacking, review, merging, crash recovery) and `code-review:review-pr` for the review process.

# Shell Tools

Use these instead of traditional Unix commands (install if missing):

| Task | Use | Not |
|------|-----|-----|
| Find files | `fd` | `find`, `ls -R` |
| Search text | `rg` | `grep`, `ag` |
| Code structure | `ast-grep` | `grep`, `sed` |
| Interactive select | `fzf` | manual filtering |
| JSON | `jq` | `python -m json.tool` |
| YAML/XML | `yq` | manual parsing |
