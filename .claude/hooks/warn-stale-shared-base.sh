#!/usr/bin/env bash
# warn-stale-shared-base.sh — PreToolUse hook (Bash matcher, filtered via "if").
# Guards against cutting a worktree/build from a stale LOCAL shared-base branch
# (ui-5.10.y, ui-6.6.y-rtd1619, master in /home/hookey/linux) that has drifted
# behind origin or carries un-pushed local commits. A real incident: a feature
# branch was cut from local ui-5.10.y 63 commits behind origin, carrying an
# unrelated local experiment that broke modpost — hours lost before the stale
# base (not the code change) was found to be the cause.
#
# Warn/confirm only — never auto-rebase or block. Dropping unpushed local
# commits via rebase-onto-origin is a destructive, user-checked decision, not
# something this hook may assume.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

# Only fire on commands that plausibly cut a worktree/branch or build from a
# shared base branch under a repo that has one. Cheap pre-filter before any
# git calls.
case "$cmd" in
  *"git worktree add"*|*debbox*make*|*make*PRODUCT=*) ;;
  *) exit 0 ;;
esac

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null || exit 0

# Shared long-lived base branches known to drift silently. Extend this list if
# other repos grow the same shared-base pattern.
SHARED_BASES=("ui-5.10.y" "ui-6.6.y-rtd1619" "master")

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$repo_root" ]] || exit 0
case "$repo_root" in
  */linux) ;;   # /home/hookey/linux (or a worktree of it) — the debbox-kernel repo
  *) exit 0 ;;
esac

# Which base does this command actually touch? Match on word boundaries so a
# branch name embedded in an unrelated token (e.g. "my-master-branch-copy")
# doesn't false-positive on "master".
target_base=""
for b in "${SHARED_BASES[@]}"; do
  if [[ "$cmd" =~ (^|[[:space:]/])"$b"($|[[:space:]/]) ]]; then
    target_base="$b"
    break
  fi
done
[[ -n "$target_base" ]] || exit 0

if ! git fetch origin "$target_base" --quiet 2>/dev/null; then
  jq -n --arg base "$target_base" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: ("⚠ Could not fetch origin/" + $base + " to verify shared-base freshness (network/auth issue?). Proceeding without this check risks inheriting stale or unrelated state — confirm the base is fresh before continuing.")
    }
  }'
  exit 0
fi

if ! behind="$(git rev-list --count "${target_base}..origin/${target_base}" 2>/dev/null)"; then
  jq -n --arg base "$target_base" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: ("⚠ Could not compare local " + $base + " against origin/" + $base + " (ref missing after fetch?). Proceeding without this check risks inheriting stale or unrelated state — confirm the base is fresh before continuing.")
    }
  }'
  exit 0
fi
ahead="$(git rev-list --count "origin/${target_base}..${target_base}" 2>/dev/null || echo 0)"

if [[ "$behind" -gt 0 || "$ahead" -gt 0 ]]; then
  msg="⚠ Shared base '${target_base}' has drifted from origin: "
  [[ "$behind" -gt 0 ]] && msg+="local is ${behind} commit(s) BEHIND origin/${target_base}. "
  [[ "$ahead" -gt 0 ]] && msg+="local carries ${ahead} commit(s) NOT on origin/${target_base} (possibly unpushed personal work). "
  msg+="Cutting a worktree or building from this base may silently inherit stale or unrelated state. "
  msg+="Confirm with the user before proceeding — e.g. 'git fetch origin && git rebase --onto origin/${target_base} ${target_base} <branch>' (this DROPS the local-only commits from the base, so it must be a checked decision, not automatic)."
  jq -n --arg msg "$msg" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $msg
    }
  }'
  exit 0
fi

exit 0
