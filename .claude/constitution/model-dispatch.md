# Model Dispatch

## Tokenizer

OLD: Opus 4.6, Sonnet 4.6, Haiku 4.5. NEW (+30% tokens): Opus 4.7/4.8, Sonnet 5.
Main session = old-tokenizer (reads most context).

## Dispatch Table

| Model | Effort | When |
|-------|--------|------|
| T0 haiku-4-5 | low | grep, locate, classify, scan |
| T1 sonnet-4-6 | high | implement, refactor, review, research, adversarial review |
| T2 opus-4-6 | high | judgment, synthesis, architectural decision |

T3 (opus-4-8) never directly dispatched — only receives escalated work.
Main session = T2. ≤1 file + bounded = inline. Otherwise subagent.

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
