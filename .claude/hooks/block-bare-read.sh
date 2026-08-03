#!/usr/bin/env bash
# block-bare-read.sh — PreToolUse hook (Bash matcher).
#
# Denies single-command cat/head/tail invocations where the Read tool is a
# direct substitute. Pipeline, redirect, compound, and heredoc usages pass
# through — those are legitimate shell-only operations.
#
# Detection logic:
# 1. Command contains |, >, >>, $(, `, &&, ;, << → allow (compound/pipe/redir)
# 2. tail with -f or --follow → allow (monitoring)
# 3. First token (after optional absolute path) is cat/head/tail → deny
# 4. Otherwise → allow
#
# Escape hatch: ALLOW_BARE_READ=1 bypasses the check.
set -euo pipefail

if [[ "${ALLOW_BARE_READ:-}" == "1" ]]; then
  exit 0
fi

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

# Step 1: allow pipelines, redirects, compound commands, subshells, heredocs
if [[ "$cmd" == *'|'* ]] || [[ "$cmd" == *'>>'* ]] || [[ "$cmd" == *'>'* ]] \
   || [[ "$cmd" == *'$('* ]] || [[ "$cmd" == *'`'* ]] \
   || [[ "$cmd" == *'&&'* ]] || [[ "$cmd" == *';'* ]] || [[ "$cmd" == *'<<'* ]]; then
  exit 0
fi

# Step 2: extract first token, stripping optional absolute path prefix
first_token="${cmd%%[[:space:]]*}"
bin="${first_token##*/}"

# Step 3: tail -f / --follow → allow (monitoring)
if [[ "$bin" == "tail" ]]; then
  if [[ "$cmd" =~ (^|[[:space:]])-f([[:space:]]|$) ]] \
     || [[ "$cmd" =~ (^|[[:space:]])--follow([[:space:]]|$) ]]; then
    exit 0
  fi
fi

# Step 4: deny bare cat/head/tail
case "$bin" in
  cat|head|tail)
    jq -n --arg bin "$bin" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Use the Read tool instead of `" + $bin + "`. Read supports offset/limit for partial reads and avoids sandbox interference.")
      }
    }'
    exit 0
    ;;
esac

# Everything else → allow
exit 0
