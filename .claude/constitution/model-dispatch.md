# Model Dispatch

## Tokenizer

OLD: Opus 4.6, Sonnet 4.6, Haiku 4.5. NEW (+30% tokens): Opus 4.7/4.8, Sonnet 5.
Main session = old-tokenizer (reads most context).

## Dispatch Table

| Tier | Model | Effort | Criterion |
|------|-------|--------|-----------|
| T0 | claude-haiku-4-5 | low | Scan: read-only or trivial substitution, structured output (grep, locate, closed-bound classify, poll, extract) |
| T1 | claude-sonnet-4-6 | high | Execute: goal clear, success verifiable (implement, test, deploy, build, correctness-focused review) |
| T2 | claude-opus-4-6 | high | Decide: trade-off judgment, no single correct answer (architecture, merge strategy, design, architectural review) |

T3 (claude-opus-4-8): escalation only — never directly dispatched.
Main session = T2. Inline when context already loaded; subagent when isolated context needed.
Do not use Explore or general-purpose agent types — plain Agent + model param.

## Model Pinning

Agent tool `model` param accepts full model ID (e.g. `claude-sonnet-4-6`), not just alias.
Alias (`sonnet`, `opus`) resolves to latest version — use full ID to prevent drift.

| Mechanism | Precedence | Scope |
|-----------|-----------|-------|
| `CLAUDE_CODE_SUBAGENT_MODEL` env var | 1 (highest) | all subagents |
| Agent tool `model` param (full ID) | 2 | single spawn |
| `.claude/agents/*.md` frontmatter `model:` | 3 | agent type |
| Inherit main session (settings.json) | 4 (fallback) | default |

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
