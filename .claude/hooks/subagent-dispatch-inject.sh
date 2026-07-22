#!/usr/bin/env bash
# SubagentStart hook: inject failure escalation + red lines into subagents,
# and record agent_id → worktree mapping for guard-agent-worktree.sh.
input="$(cat)"

# --- Agent-map: record assigned worktree for isolation guard ---
agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)"
prompt="$(printf '%s' "$input" | jq -r '.subagent_prompt // empty' 2>/dev/null)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

if [ -n "$agent_id" ] && [ -n "$prompt" ] && [ -n "$PROJECT_DIR" ]; then
  worktree=""
  if [[ "$prompt" =~ \.worktrees/[^[:space:]\"\']+ ]]; then
    candidate="${BASH_REMATCH[0]}"
    candidate="${candidate%%\"*}"
    candidate="${candidate%%\'*}"
    candidate="${candidate%%\`*}"
    case "$candidate" in
      /*) abs="$candidate" ;;
      *)  abs="$PROJECT_DIR/$candidate" ;;
    esac
    worktree="$(realpath -m "$abs" 2>/dev/null || echo "$abs")"
  fi
  if [ -n "$worktree" ]; then
    map_dir="$PROJECT_DIR/.worktrees/.agent-map"
    mkdir -p "$map_dir"
    printf '%s' "$worktree" > "$map_dir/$agent_id"
  fi
fi

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
