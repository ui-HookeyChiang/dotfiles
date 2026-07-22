#!/usr/bin/env bash
# guard-stale-base.sh — PreToolUse hook (Bash matcher).
#
# Guards branch-CREATION commands against a stale local start-point:
# - Bare local branch ref as start-point → deny (may be stale / unpushed)
# - Remote-prefixed ref (origin/main, upstream/dev) → allow + cached fetch
# - Tag or SHA → allow (immutable)
#
# Only these creation forms are inspected (a start-point must be explicit):
#   git checkout -b <name> <start-point>
#   git switch   -c <name> <start-point>
#   git branch      <name> <start-point>   (only when <name> is NOT an option)
#   git worktree add [<path>] <start-point>
#   git worktree add [<path>] -b <name> <start-point>
#
# Deliberately NOT inspected (no start-point, or not a creation):
#   git branch -d/-D/--list/-m/-r/-a/--merged ...  (deletion/listing/rename)
#   git checkout -b <name>  /  git switch -c <name> (no start-point → from HEAD)
#   git branch <name>                               (no start-point → from HEAD)
# The command is truncated at the first shell separator/redirection, so text
# inside a heredoc / commit message / PR body cannot trip the matcher.
#
# Escape hatch: ALLOW_STALE_BASE=1 bypasses the check (allow).
set -euo pipefail

if [[ "${ALLOW_STALE_BASE:-}" == "1" ]]; then
  exit 0
fi

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Anchor to the first command only: drop everything from the first shell
# separator or redirection onward. Prevents heredoc / message bodies and
# `2>&1`-style tokens from being parsed as git arguments.
first_cmd="${cmd%%;*}"
first_cmd="${first_cmd%%&&*}"
first_cmd="${first_cmd%%||*}"
first_cmd="${first_cmd%%|*}"
# Strip redirections, including an optional leading fd number (e.g. `2>&1`):
# drop from the fd-digit+'>' or a bare '>' / '<' onward.
first_cmd="$(printf '%s' "$first_cmd" | sed -E 's/[[:space:]]+[0-9]*[<>].*$//')"

# A start-point token must be a plain ref: no leading '-' (option/redirect),
# no shell metacharacters.
sp='([^-[:space:];&|<>][^[:space:];&|<>]*)'

# --- Extract the start-point from a branch-CREATION command -----------------
# checkout -b <name> <start-point>  /  switch -c <name> <start-point>
co_pattern="git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c)[[:space:]]+[^[:space:]]+[[:space:]]+$sp"
# branch <name> <start-point>  — <name> must NOT be an option (excludes -d/-D/
# --list/-m/…), and a start-point must follow.
branch_pattern="git[[:space:]]+branch[[:space:]]+([^-[:space:]][^[:space:]]*)[[:space:]]+$sp"
# worktree add [<path>] -b <name> <start-point>
worktree_b_pattern="git[[:space:]]+worktree[[:space:]]+add[[:space:]]+[^[:space:]]+[[:space:]]+-b[[:space:]]+[^[:space:]]+[[:space:]]+$sp"
# worktree add <path> <start-point>  (no -b)
worktree_pattern="git[[:space:]]+worktree[[:space:]]+add[[:space:]]+[^[:space:]]+[[:space:]]+$sp"

base=""
if [[ "$first_cmd" =~ $worktree_b_pattern ]]; then
  base="${BASH_REMATCH[1]}"
elif [[ "$first_cmd" =~ $co_pattern ]]; then
  base="${BASH_REMATCH[2]}"
elif [[ "$first_cmd" =~ $branch_pattern ]]; then
  base="${BASH_REMATCH[2]}"
elif [[ "$first_cmd" =~ $worktree_pattern ]]; then
  base="${BASH_REMATCH[1]}"
fi

[[ -n "$base" ]] || exit 0

# --- Classify the start-point ref -------------------------------------------

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
    permissionDecisionReason: ("Blocked: branching from local `" + $base + "` — may be stale or carry unpushed commits. Use a remote ref (e.g. `origin/" + $base + "`) instead.\n\n  command: " + $cmd + "\n  fix: replace `" + $base + "` with `origin/" + $base + "`, or set ALLOW_STALE_BASE=1.")
  }
}'
