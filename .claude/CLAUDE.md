# Task Planning

For tasks with 4+ steps or significant complexity, enter plan mode first before implementing. This ensures alignment and prevents wasted effort.

Persist task progress to the project's `TASK.md` (at the project root) so work can resume after agent restarts or context resets:
- **On start:** Check `TASK.md` for in-progress work and resume where left off
- **During work:** Update `TASK.md` as tasks are completed or new ones discovered
- **On completion:** Remove finished tasks from `TASK.md`

# Skills

Before invoking a skill or running its scripts, read the SKILL.md first to understand what it does, its prerequisites, and expected output. Do not blindly execute.

When a skill or task will produce large output or run for a long time (builds, bulk data collection, test runs, log gathering), delegate it to a subagent to prevent context pollution. Keep the main conversation context clean for decision-making.

After running a skill, if any problems occur (wrong output, missing steps, outdated commands, unclear instructions), fix the skill's SKILL.md, scripts, or references to prevent the issue from recurring. Use `skill-creator` to validate changes.

# Git Feature Development

When developing features under git, use **stacked PRs** as the default workflow:

1. **Split** the feature into small, independent tasks (each <500 lines changed)
2. **Use git worktrees** — one per task, so the main working tree stays undisturbed
3. **Stack PRs** — each task's PR targets the previous task's branch (task-1 → main, task-2 → task-1, etc.)
4. **Review in parallel** — launch `code-review:review-pr` agents for each PR plus one overall feature review

See the `stacking-feature-dev` skill for the full workflow, and `code-review:review-pr` for the review process.

# Shell Tools Usage Guidelines

**IMPORTANT**: Use the following specialized tools instead of traditional Unix commands (install if missing):

| Task Type | Must Use | Do Not Use |
|-----------|----------|------------|
| Find Files | `fd` (fd-find) | `find`, `ls -R` |
| Search Text | `rg` (ripgrep) | `grep`, `ag` |
| Analyze Code Structure | `ast-grep` | `grep`, `sed` |
| Interactive Selection | `fzf` | Manual filtering |
| Process JSON | `jq` | `python -m json.tool` |
| Process YAML/XML | `yq` | Manual parsing |

## Installation (macOS)

```bash
brew install fd ripgrep ast-grep fzf jq yq
```

## Installation (Ubuntu/Debian)

```bash
sudo apt install fd-find ripgrep fzf jq
# For ast-grep and yq, use cargo or download binaries
```

