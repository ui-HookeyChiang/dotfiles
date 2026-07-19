# Model Dispatch

| Agent | Criterion |
|-------|-----------|
| `scan` | Bounded — input contains all needed info (grep, locate, classify, extract) |
| `execute` | Goal clear, success verifiable (implement, test, deploy, build, review) |
| `decide` | Trade-off judgment, no single correct answer (architecture, design, merge strategy) |

## Escalation

Subagent completes 3-step failure methodology before returning (enforced by SubagentStart hook):
switch approach → reframe with 3 hypotheses → full checklist. Cannot report failure before step 3.

Before escalating, judge the failure type: capability gap → escalate; context/tools gap → surface to user directly.

| Failed agent | Escalate to |
|-------------|-------------|
| `execute` | `decide` |
| `decide` | `fable` [low] |
| fable [low] | Surface to user |

## Delegation

Every dispatch: **goal+why**, **acceptance criteria** (checkable), **report format** (<200 words, file:line).
Verify ≠ self-verify: code → run tests; judgment → fresh-context subagent argues other side.
