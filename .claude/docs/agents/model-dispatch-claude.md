# Model Dispatch

## Dispatch Table

| Tier | Model | Effort | Criterion |
|------|-------|--------|-----------|
| T0 | claude-haiku-4-5 | low | Scan: bounded — input contains all needed information (grep, locate, classify, substitute, poll, extract) |
| T1 | claude-sonnet-4-6 | high | Execute: goal clear, success verifiable (implement, test, deploy, build, correctness-focused review) |
| T2 | claude-opus-4-6 | high | Decide: trade-off judgment, no single correct answer (architecture, merge strategy, design, architectural review) |

T3 (claude-opus-4-8): escalation only — never directly dispatched.
Main session = T2. Inline when context already loaded; subagent when isolated context needed.
Do not use Explore or general-purpose agent types — plain Agent + model param.

## Model Pinning

Agent tool `model` param accepts **aliases only** (`sonnet`, `opus`, `haiku`, `fable`). Aliases resolve to latest version.
To pin a specific version, use `~/.claude/agents/*.md` definition files — frontmatter `model:` accepts full model IDs (e.g. `model: claude-sonnet-4-6`).

| Mechanism | Precedence | Scope |
|-----------|-----------|-------|
| `CLAUDE_CODE_SUBAGENT_MODEL` env var | 1 (highest) | all subagents |
| Agent tool `model` param (alias only) | 2 | single spawn |
| `.claude/agents/*.md` frontmatter `model:` | 3 | agent type |
| Inherit main session (settings.json) | 4 (fallback) | default |

## Agent Definitions (~/.claude/agents/)

Three agent definitions pin model versions for dispatch tiers:

| Agent | File | Model | Tier |
|-------|------|-------|------|
| `scan` | `~/.claude/agents/scan.md` | `haiku` | T0 |
| `execute` | `~/.claude/agents/execute.md` | `claude-sonnet-4-6` | T1 |
| `decide` | `~/.claude/agents/decide.md` | `claude-opus-4-6` | T2 |

Usage: `Agent(subagent_type: "execute", prompt: "...")` — model resolved from frontmatter.
Required frontmatter: `name`, `description`, `model`, `color`. Missing fields = silently ignored by registry.

## Leader Escalation

Subagent returns failure report ONLY after exhausting its internal methodology
(3 approach switches minimum — enforced by SubagentStart hook). On receiving failure:

| Failed tier | Action |
|-------------|--------|
| T1 | Re-dispatch same goal as T2 |
| T2 | Re-dispatch same goal as T3 [high] |
| T3 [high] | Retry as T3 [max] |
| T3 [max] | Surface to user |

## Delegation Triad

Every dispatch: **goal+why**, **acceptance criteria** (checkable), **report format** (<200 words, file:line).
Verify ≠ self-verify: code → run tests; judgment → fresh-context subagent argues other side.
