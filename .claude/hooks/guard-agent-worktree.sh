#!/usr/bin/env bash
# PreToolUse hook: enforce subagent worktree isolation.
#
# Guard legs:
# 1. Mapped subagent: deny file-tool writes outside assigned worktree;
#    deny write-type git from outside assigned worktree.
# 2. Main session (no agent_id): deny file-tool writes INTO .worktrees/**
#    (worktree files belong to the task's dev agent). Bash ungated.
# 3. Session claim: concurrent main sessions in one checkout — first writer
#    claims; others denied until TTL (30min) expires or ALLOW_SESSION_TAKEOVER=1.
# 4. Worktree lifecycle (all sessions):
#    a) Bash rm -rf on a registered worktree → deny (use git worktree remove).
#    b) File-tool/git-add writes into orphan worktree dir (under .worktrees/
#       but not in `git worktree list`) → deny.
#
# Escape hatches: ALLOW_MAIN_EDIT=1 (leg 2), ALLOW_SESSION_TAKEOVER=1 (leg 3),
#                 ALLOW_WORKTREE_LIFECYCLE=1 (leg 4).
set -uo pipefail

input="$(cat)"

agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
[ -z "$PROJECT_DIR" ] && exit 0

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

is_under() {
  local path="$1" prefix="$2"
  case "$path" in
    "$prefix"|"$prefix"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Extract target file paths from apply_patch unified diff input.
# Returns newline-separated absolute paths (resolved via realpath -m).
apply_patch_paths() {
  local patch="$1" base_dir="$2"
  printf '%s' "$patch" | grep -E '^\+\+\+ b/' | sed 's|^+++ b/||' | while IFS= read -r rel; do
    realpath -m "$base_dir/$rel" 2>/dev/null || echo "$base_dir/$rel"
  done
}

# ── Leg 4: Worktree lifecycle (all sessions) ─────────────────────────────
if [ "${ALLOW_WORKTREE_LIFECYCLE:-}" != "1" ]; then
  WORKTREE_CONTAINERS=()
  for d in "$PROJECT_DIR/.worktrees" "$PROJECT_DIR/.worktree"; do
    [ -d "$d" ] && WORKTREE_CONTAINERS+=("$(realpath -m "$d" 2>/dev/null || echo "$d")")
  done

  if [ ${#WORKTREE_CONTAINERS[@]} -gt 0 ]; then
    # 4a: Bash rm -rf on a registered worktree → deny
    if [ "$tool_name" = "Bash" ]; then
      cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
      RM_PATTERN='rm[[:space:]]+-[[:alnum:]]*r[[:alnum:]]*f[[:alnum:]]*[[:space:]]+([^;&|]+)'
      if [[ "${cmd:-}" =~ $RM_PATTERN ]]; then
        rm_target="${BASH_REMATCH[1]}"
        rm_target="${rm_target%% *}"
        rm_resolved="$(realpath -m "$rm_target" 2>/dev/null || echo "$rm_target")"
        for container in "${WORKTREE_CONTAINERS[@]}"; do
          if is_under "$rm_resolved" "$container" && [ "$rm_resolved" != "$container" ]; then
            if git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | grep -qF "worktree $rm_resolved"; then
              deny "Blocked: rm -rf on registered worktree $rm_resolved.

Use \`git worktree remove\` instead (refuses when dirty, preserving unsaved work):

  git worktree remove $rm_resolved
  git worktree prune

Escape hatch: ALLOW_WORKTREE_LIFECYCLE=1."
            fi
          fi
        done
      fi
    fi

    # 4b: File tools / git add into orphan worktree dir → deny
    # An orphan is a dir under .worktrees/ that has no .git file (not a
    # checked-out worktree) and is not in `git worktree list`.
    # Skip if the agent is mapped to this path (Leg 1 handles isolation).
    resolve_file_target() {
      local fp=""
      case "$tool_name" in
        Edit|Write|MultiEdit|NotebookEdit)
          fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
          ;;
        apply_patch)
          fp="$(printf '%s' "$input" | jq -r '.tool_input.patch // .tool_input.command // empty' 2>/dev/null \
            | grep -m1 -E '^\+\+\+ b/' | sed 's|^+++ b/||')"
          [ -n "$fp" ] && case "$fp" in /*) ;; *) fp="$PROJECT_DIR/$fp" ;; esac
          ;;
        Bash)
          local c="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
          local GIT_ADD_RE='git[[:space:]]+add[[:space:]]+(-[fA][[:space:]]+)?([^;&|[:space:]]+)'
          if [[ "${c:-}" =~ $GIT_ADD_RE ]]; then
            fp="${BASH_REMATCH[2]}"
          fi
          ;;
      esac
      [ -n "$fp" ] && realpath -m "$fp" 2>/dev/null || echo "$fp"
    }

    # Check if agent is mapped — if so, skip orphan check (Leg 1 handles it)
    _agent_assigned=""
    if [ -n "$agent_id" ] && [ -f "$PROJECT_DIR/.worktrees/.agent-map/$agent_id" ]; then
      _agent_assigned="$(cat "$PROJECT_DIR/.worktrees/.agent-map/$agent_id" 2>/dev/null)"
    fi

    target_resolved="$(resolve_file_target)"
    if [ -n "$target_resolved" ]; then
      for container in "${WORKTREE_CONTAINERS[@]}"; do
        if is_under "$target_resolved" "$container"; then
          rel="${target_resolved#$container/}"
          wt_subdir="${rel%%/*}"
          [ -z "$wt_subdir" ] && continue
          wt_path="$container/$wt_subdir"
          # Allow second-level nesting: .worktrees/ns/task-1
          if [ -d "$wt_path" ] && [ ! -f "$wt_path/.git" ]; then
            sub_rel="${rel#$wt_subdir/}"
            sub_subdir="${sub_rel%%/*}"
            [ -n "$sub_subdir" ] && [ -d "$wt_path/$sub_subdir" ] && wt_path="$wt_path/$sub_subdir"
          fi
          # Skip if this is the agent's assigned worktree
          [ -n "$_agent_assigned" ] && is_under "$target_resolved" "$_agent_assigned" && continue
          # Skip for main session if ALLOW_MAIN_EDIT=1
          [ -z "$agent_id" ] && [ "${ALLOW_MAIN_EDIT:-}" = "1" ] && continue
          if [ -d "$wt_path" ] && [ ! -f "$wt_path/.git" ] && ! git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | grep -qF "worktree $wt_path"; then
            deny "Blocked: write targets orphan worktree directory $wt_path.

This path is under $container but is NOT a registered git worktree.
It may be a leftover from an improperly removed worktree. Files written
here end up in the main repo at a stray path.

Fix: delete the orphan directory, or recreate the worktree:

  rm -rf $wt_path
  git worktree prune

Escape hatch: ALLOW_WORKTREE_LIFECYCLE=1."
          fi
        fi
      done
    fi
  fi
fi

# ── Leg 2: Main session — session claim + deny writes into .worktrees/** ──
if [ -z "$agent_id" ]; then
  [ "${ALLOW_MAIN_EDIT:-}" = "1" ] && exit 0

  WORKTREES_DIR="$(realpath -m "$PROJECT_DIR/.worktrees" 2>/dev/null || echo "$PROJECT_DIR/.worktrees")"
  [ -d "$PROJECT_DIR/.worktrees" ] || exit 0

  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  CLAIM_FILE="$PROJECT_DIR/.worktrees/.session-claim"
  SESSION_CLAIM_TTL="${SESSION_CLAIM_TTL:-1800}"

  is_write_op=false
  case "$tool_name" in
    Edit|Write|MultiEdit|NotebookEdit|apply_patch)
      is_write_op=true
      ;;
    Bash)
      cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
      WRITE_GIT_RE='git[[:space:]]+(commit|push|checkout|switch|branch[[:space:]]+-[dD]|reset|rebase|merge|cherry-pick|am|stash[[:space:]]+(drop|pop|clear))'
      [[ "${cmd:-}" =~ $WRITE_GIT_RE ]] && is_write_op=true
      ;;
  esac

  if [ "$is_write_op" = true ] && [ -n "$session_id" ]; then
    if [ -f "$CLAIM_FILE" ]; then
      holder="$(cat "$CLAIM_FILE" 2>/dev/null)"
      if [ "$holder" != "$session_id" ]; then
        claim_age=0
        if [ -f "$CLAIM_FILE" ]; then
          claim_mtime="$(stat -c %Y "$CLAIM_FILE" 2>/dev/null || stat -f %m "$CLAIM_FILE" 2>/dev/null || echo 0)"
          now="$(date +%s)"
          claim_age=$(( now - claim_mtime ))
        fi

        if [ "$claim_age" -ge "$SESSION_CLAIM_TTL" ]; then
          printf '%s' "$session_id" > "$CLAIM_FILE"
        elif [ "${ALLOW_SESSION_TAKEOVER:-}" = "1" ]; then
          printf '%s' "$session_id" > "$CLAIM_FILE"
        else
          ago_min=$(( claim_age / 60 ))
          deny "Blocked: checkout held by session $holder (active ${ago_min}m ago).

Use EnterWorktree to get your own worktree, or set ALLOW_SESSION_TAKEOVER=1 to take over."
        fi
      else
        touch "$CLAIM_FILE"
      fi
    else
      # First write — create claim (noclobber race: loser is denied next call)
      ( set -C; printf '%s' "$session_id" > "$CLAIM_FILE" ) 2>/dev/null || true
    fi
  fi

  # Deny file-tool writes into .worktrees/**
  case "$tool_name" in
    Edit|Write|MultiEdit|NotebookEdit)
      file_path="$(printf '%s' "$input" \
        | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
      [ -z "$file_path" ] && exit 0

      resolved="$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")"
      if is_under "$resolved" "$WORKTREES_DIR"; then
        deny "Blocked: worktree files belong to the task's dev agent — dispatch a fix loop instead.

Target: $resolved
Worktrees root: $WORKTREES_DIR

To bypass: set ALLOW_MAIN_EDIT=1."
      fi
      ;;
    apply_patch)
      patch="$(printf '%s' "$input" | jq -r '.tool_input.patch // .tool_input.command // empty' 2>/dev/null)"
      [ -z "$patch" ] && exit 0
      while IFS= read -r resolved; do
        if is_under "$resolved" "$WORKTREES_DIR"; then
          deny "Blocked: worktree files belong to the task's dev agent — dispatch a fix loop instead.

Target: $resolved
Worktrees root: $WORKTREES_DIR

To bypass: set ALLOW_MAIN_EDIT=1."
        fi
      done < <(apply_patch_paths "$patch" "$PROJECT_DIR")
      ;;
  esac
  exit 0
fi

# ── Leg 1: Mapped subagent — deny writes outside assigned worktree ────────
MAP_FILE="$PROJECT_DIR/.worktrees/.agent-map/$agent_id"
[ -f "$MAP_FILE" ] || exit 0

ASSIGNED="$(cat "$MAP_FILE")"
[ -z "$ASSIGNED" ] && exit 0

is_allowed_path() {
  local resolved="$1"
  is_under "$resolved" "$ASSIGNED" && return 0
  if ! is_under "$resolved" "$PROJECT_DIR"; then
    local tmp="${TMPDIR:-/tmp}"
    tmp="$(realpath -m "$tmp" 2>/dev/null || echo "$tmp")"
    is_under "$resolved" "$tmp" && return 0
    is_under "$resolved" "/tmp" && return 0
  fi
  return 1
}

# --- File tools ---
case "$tool_name" in
  Edit|Write|MultiEdit|NotebookEdit)
    file_path="$(printf '%s' "$input" \
      | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
    [ -z "$file_path" ] && exit 0

    resolved="$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")"
    if ! is_allowed_path "$resolved"; then
      deny "Blocked: write to $resolved is outside your assigned worktree.

Your worktree: $ASSIGNED

Re-issue the edit targeting a path inside your worktree, or use /tmp for scratch files."
    fi
    exit 0
    ;;
  apply_patch)
    patch="$(printf '%s' "$input" | jq -r '.tool_input.patch // .tool_input.command // empty' 2>/dev/null)"
    [ -z "$patch" ] && exit 0
    patch_cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
    [ -z "$patch_cwd" ] && patch_cwd="$PROJECT_DIR"
    while IFS= read -r resolved; do
      if ! is_allowed_path "$resolved"; then
        deny "Blocked: apply_patch targets $resolved which is outside your assigned worktree.

Your worktree: $ASSIGNED

Re-issue the patch targeting files inside your worktree, or use /tmp for scratch files."
      fi
    done < <(apply_patch_paths "$patch" "$patch_cwd")
    exit 0
    ;;
esac

# --- Bash: write-type git heuristic ---
if [ "$tool_name" = "Bash" ]; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [ -z "$cmd" ] && exit 0

  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
  [ -z "$cwd" ] && cwd="${PWD}"
  resolved_cwd="$(realpath -m "$cwd" 2>/dev/null || echo "$cwd")"

  is_under "$resolved_cwd" "$ASSIGNED" && exit 0

  WRITE_GIT_PATTERN='git[[:space:]]+(commit|push|checkout|switch|branch[[:space:]]+-[dD]|reset|rebase|merge|cherry-pick|am|stash[[:space:]]+(drop|pop|clear))'
  if [[ "$cmd" =~ $WRITE_GIT_PATTERN ]]; then
    GIT_C_PATTERN='git[[:space:]]+-C[[:space:]]+([^[:space:];&|]+)'
    if [[ "$cmd" =~ $GIT_C_PATTERN ]]; then
      c_path="${BASH_REMATCH[1]}"
      resolved_c="$(realpath -m "$c_path" 2>/dev/null || echo "$c_path")"
      is_under "$resolved_c" "$ASSIGNED" && exit 0
    fi

    deny "Blocked: write-type git operation from outside your assigned worktree.

  cwd: $resolved_cwd
  command: $cmd
  your worktree: $ASSIGNED

Run this command from inside your worktree, or use git -C $ASSIGNED <command>."
  fi
fi

exit 0
