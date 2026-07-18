#!/usr/bin/env bash
# guard-stale-base.sh — PreToolUse hook (Bash matcher).
#
# Guards branching commands:
# - Bare local branch ref → deny (may be stale or carry unpushed commits)
# - Remote-prefixed ref (origin/main, upstream/dev) → allow + cached fetch
# - Tag or SHA → allow (immutable)
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# --- Extract base ref from branching commands ---
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

# --- Classify the base ref ---

# SHA (hex, 7-40 chars) → immutable, allow
[[ "$base" =~ ^[0-9a-f]{7,40}$ ]] && exit 0

# Tag → immutable, allow
git rev-parse --verify --quiet "refs/tags/$base" >/dev/null 2>&1 && exit 0

# Remote-prefixed (any remote) → cached fetch, allow
remotes="$(git remote 2>/dev/null || true)"
for remote in $remotes; do
  case "$base" in
    "${remote}"/*)
      # Cached fetch: skip if fetched within 5 minutes
      gitdir="$(git rev-parse --absolute-git-dir 2>/dev/null)"
      stamp="$gitdir/.guard-fetch-stamp"
      now="$(date +%s)"
      last="$(cat "$stamp" 2>/dev/null || echo 0)"
      if (( now - last > 300 )); then
        git fetch --all --quiet 2>/dev/null && printf '%s' "$now" > "$stamp"
      fi
      exit 0
      ;;
  esac
done

# Bare local ref → deny
jq -n --arg base "$base" --arg cmd "$cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Blocked: branching from local `" + $base + "` — may be stale or carry unpushed commits. Use a remote ref (e.g. `origin/" + $base + "`) instead.\n\n  command: " + $cmd + "\n  fix: replace `" + $base + "` with `origin/" + $base + "`")
  }
}'
