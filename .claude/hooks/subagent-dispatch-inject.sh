#!/usr/bin/env bash
# SubagentStart hook: inject failure escalation + red lines into subagents.
cat > /dev/null

RULES='## Delivery Red Lines
1. CLOSE THE LOOP: "done" requires evidence (test output, build log). No evidence = not done.
2. FACT-DRIVEN: verify before blaming. Use tools to confirm before attributing cause.
3. EXHAUST METHODOLOGY: complete all escalation steps below before reporting failure.

## Failure Escalation (self-enforce)
Track consecutive tool failures. Classify pattern:
- SPINNING (same error repeats): you are retrying same approach. STOP. Switch immediately.
- EXPLORING (different errors each time): keep going, you are making progress.

On each failure:
1. Switch approach (never retry same command/strategy)
2. Reframe: 3 hypotheses, read source, search
3. Full checklist: verify assumptions, read error word-by-word, check logs
4+. STOP. Return failure report: what tried, what failed, root cause hypothesis

Cannot report failure before step 3. Red line 3 enforces this.'

jq -nc --arg c "$RULES" '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$c}}'
