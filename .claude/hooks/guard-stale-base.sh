#!/usr/bin/env bash
# guard-stale-base.sh — unified stale-base guard (PreToolUse hook, Bash matcher).
#
# Merges two concerns:
# 1. BLOCK branching from bare main/master (forces origin/main)
# 2. WARN if a shared base branch has drifted from origin
#
# Config: .guard-stale-base.json at repo root, or global ~/.claude/guard-stale-base.json.
# Format:
#   {
#     "shared_bases": ["ui-5.10.y", "master"],
#     "triggers": ["git worktree add", "make PRODUCT="]
#   }
# Without config, only the bare-main block (1) runs.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null || exit 0

# Is this a git repo?
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# --- Part 1: Block branching from bare main/master ---
# Catches: git checkout -b <branch> main, git switch -c <branch> main,
#          git branch <name> main, git worktree add <path> -b <branch> main
bare_main_pattern='(git\s+(checkout\s+-b|switch\s+-c|branch\s+[^-]|worktree\s+add\s+)\S+\s+)(main|master)\s*($|[;&|])'

if [[ "$cmd" =~ $bare_main_pattern ]]; then
  base="${BASH_REMATCH[3]}"
  jq -n --arg base "$base" --arg cmd "$cmd" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Blocked: branching from local `" + $base + "` is forbidden. Local " + $base + " may carry stale or unpushed commits. Use `origin/" + $base + "` instead.\n\n  command: " + $cmd + "\n  fix: git fetch origin && <same command with origin/" + $base + ">")
    }
  }'
  exit 0
fi

# --- Part 2: Warn on stale shared base branches ---
# Load config (repo-local first, then global fallback)
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
config=""
if [[ -n "$repo_root" ]] && [[ -f "$repo_root/.guard-stale-base.json" ]]; then
  config="$repo_root/.guard-stale-base.json"
elif [[ -f "$HOME/.claude/guard-stale-base.json" ]]; then
  config="$HOME/.claude/guard-stale-base.json"
fi

# No config = no shared-base checking (part 1 still runs above)
[[ -n "$config" ]] || exit 0

# Check if command matches any trigger
triggers=$(jq -r '.triggers[]?' "$config" 2>/dev/null)
matched_trigger=false
while IFS= read -r trigger; do
  [[ -z "$trigger" ]] && continue
  [[ "$cmd" == *"$trigger"* ]] && { matched_trigger=true; break; }
done <<< "$triggers"
$matched_trigger || exit 0

# Find which shared base this command references
shared_bases=$(jq -r '.shared_bases[]?' "$config" 2>/dev/null)
target_base=""
while IFS= read -r b; do
  [[ -z "$b" ]] && continue
  if [[ "$cmd" =~ (^|[[:space:]/])"$b"($|[[:space:]/]) ]]; then
    target_base="$b"
    break
  fi
done <<< "$shared_bases"
[[ -n "$target_base" ]] || exit 0

# Fetch and compare
if ! git fetch origin "$target_base" --quiet 2>/dev/null; then
  jq -n --arg base "$target_base" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: ("⚠ Could not fetch origin/" + $base + " to verify freshness. Proceeding risks inheriting stale state — confirm the base is fresh.")
    }
  }'
  exit 0
fi

behind="$(git rev-list --count "${target_base}..origin/${target_base}" 2>/dev/null || echo 0)"
ahead="$(git rev-list --count "origin/${target_base}..${target_base}" 2>/dev/null || echo 0)"

if [[ "$behind" -gt 0 || "$ahead" -gt 0 ]]; then
  msg="⚠ Shared base '${target_base}' drifted from origin: "
  [[ "$behind" -gt 0 ]] && msg+="${behind} commit(s) BEHIND. "
  [[ "$ahead" -gt 0 ]] && msg+="${ahead} local-only commit(s). "
  msg+="Run: git fetch origin && git checkout ${target_base} && git rebase origin/${target_base}"
  jq -n --arg msg "$msg" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $msg
    }
  }'
  exit 0
fi

exit 0
