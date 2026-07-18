#!/usr/bin/env bash
# guard-stale-base.sh — PreToolUse hook (Bash matcher).
#
# Two guards on branching commands:
# 1. Base ref without `origin/` prefix — denied (local may be stale)
# 2. Base ref with `origin/` prefix — fetched first to ensure fresh
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Match branching commands and extract the base ref (last positional arg).
# Patterns:
#   git checkout -b <new> <base>
#   git switch -c <new> <base>
#   git branch <new> <base>
#   git worktree add <path> -b <new> <base>
#   git worktree add <path> <base>         (no -b, base is existing branch)
branch_pattern='git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c|branch)[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:];&|]+)'
worktree_b_pattern='git[[:space:]]+worktree[[:space:]]+add[[:space:]]+[^[:space:]]+[[:space:]]+-b[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:];&|]+)'
worktree_pattern='git[[:space:]]+worktree[[:space:]]+add[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:];&|-][^[:space:];&|]*)'

base=""
if [[ "$cmd" =~ $worktree_b_pattern ]]; then
  base="${BASH_REMATCH[1]}"
elif [[ "$cmd" =~ $branch_pattern ]]; then
  base="${BASH_REMATCH[2]}"
elif [[ "$cmd" =~ $worktree_pattern ]]; then
  base="${BASH_REMATCH[1]}"
fi

[[ -n "$base" ]] || exit 0

# origin/ prefix = remote ref — fetch to ensure fresh, then allow
case "$base" in
  origin/*)
    ref_name="${base#origin/}"
    if ! git fetch origin "$ref_name" --quiet 2>/dev/null; then
      jq -n --arg base "$base" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "ask",
          permissionDecisionReason: ("⚠ Could not fetch " + $base + " to verify freshness. Proceeding risks branching from stale state.")
        }
      }'
    fi
    exit 0
    ;;
esac

# Bare local ref — deny
jq -n --arg base "$base" --arg cmd "$cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Blocked: branching from local `" + $base + "` — may be stale or carry unpushed commits. Use `origin/" + $base + "` instead.\n\n  command: " + $cmd + "\n  fix: replace `" + $base + "` with `origin/" + $base + "`")
  }
}'
