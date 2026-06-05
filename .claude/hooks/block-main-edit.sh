#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): per-workdir occupancy lock.
#
# Semantics: one Claude session at a time per git working directory (worktree
# toplevel / main checkout). The first session to edit inside a workdir claims
# it; a second concurrent session is blocked and nudged to create its own
# worktree. This replaces the older "block all edits on main/master" rule —
# main is no longer special; whoever claims it first may develop there.
#
# Lock:     <git-dir>/claude-session.lock   (one per workdir; git-dir differs
#           per linked worktree, so locks never collide across worktrees)
# Format:   <session_id>\t<transcript_path>\t<claim_epoch>   (TSV, one line)
# Release:  release-session-lock.sh on SessionEnd (owner deletes its own lock);
#           crash recovery via a long staleness timeout (see STALE_SECS).
# Liveness: the owner's transcript_path mtime — Claude appends a turn to the
#           transcript on activity, so a live session's transcript advances and
#           a dead one's goes quiet. Deliberately conservative (6h) so we never
#           steal a lock from a session that is merely thinking for a long time.
#
# Escape hatch: ALLOW_MAIN_EDIT=1 bypasses the lock entirely (kept for the
# legitimate cases the old hook documented — initial commit, editing this hook
# / settings.json itself, an urgent hotfix, or a deliberate single-operator run).
set -uo pipefail

# --- Tunables ---------------------------------------------------------------
STALE_SECS="${CLAUDE_LOCK_STALE_SECS:-21600}"  # 6h; fail-safe, do not lower lightly
MUTEX_STALE_SECS=30                            # abandoned mkdir-mutex reaper

# --- Escape hatch -----------------------------------------------------------
if [ "${ALLOW_MAIN_EDIT:-}" = "1" ]; then
  exit 0
fi

# --- Parse hook input -------------------------------------------------------
input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
# NotebookEdit carries notebook_path instead of file_path; fall back to either.
file_path="$(printf '%s' "$input" \
  | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"

if [ -n "$file_path" ]; then
  dir="$(dirname "$file_path")"
else
  dir="${PWD}"
fi
# Resolve a relative file_path against PWD so git -C lands in the right repo.
case "$dir" in
  /*) ;;
  *)  dir="${PWD}/${dir}" ;;
esac

# Without a session_id we cannot own a lock; fail open (matches old allow path).
if [ -z "$session_id" ]; then
  exit 0
fi

deny() {  # $1 = reason
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# --- Resolve the workdir lock path (key on git-dir, NOT branch) -------------
# git-dir is per-worktree, so this is the natural per-workdir key and works
# for detached HEAD too (the old hook's empty-branch early-exit allowed those).
gitdir="$(git -C "$dir" rev-parse --git-dir 2>/dev/null)" || exit 0  # not a repo -> allow
[ -z "$gitdir" ] && exit 0
case "$gitdir" in
  /*) ;;
  *)  gitdir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir="${dir}/${gitdir}" ;;
esac
lock="${gitdir}/claude-session.lock"
mutex="${lock}.mx"

now="$(date +%s)"

is_alive() {  # $1 = transcript_path, $2 = claim_epoch  -> 0 if alive
  local tx="$1" ts="$2" mtime
  # Never steal within the same wall-clock minute, regardless of signal.
  if [ -n "$ts" ] && [ $((now - ts)) -lt 60 ]; then
    return 0
  fi
  if [ -n "$tx" ] && [ -f "$tx" ]; then
    mtime="$(stat -c %Y "$tx" 2>/dev/null || echo 0)"
    [ $((now - mtime)) -lt "$STALE_SECS" ] && return 0
    return 1
  fi
  # Transcript gone: fall back to the lock's own claim timestamp.
  [ -n "$ts" ] && [ $((now - ts)) -lt "$STALE_SECS" ] && return 0
  return 1
}

write_lock() {  # atomic replace via temp + mv (mv is atomic within a fs)
  local tmp
  tmp="$(mktemp "${lock}.XXXXXX")" || return 1
  printf '%s\t%s\t%s\n' "$session_id" "$transcript_path" "$now" > "$tmp" \
    && mv -f "$tmp" "$lock"
}

# Read the lock into owner/owner_tx/owner_ts. Returns 1 if the file is missing
# or malformed (fewer than the 3 expected non-empty TSV fields) so callers can
# treat a corrupt lock as "no valid owner" rather than mis-parsing it.
read_lock() {  # populates globals: owner owner_tx owner_ts
  owner=""; owner_tx=""; owner_ts=""
  [ -f "$lock" ] || return 1
  IFS=$'\t' read -r owner owner_tx owner_ts < "$lock"
  [ -n "$owner" ] && [ -n "$owner_ts" ] || return 1
  return 0
}

# --- Fast path: existing lock -----------------------------------------------
# A malformed lock (read_lock returns 1) is treated as "no valid owner" and
# falls through to a fresh claim below, which overwrites the corrupt file.
if read_lock; then
  if [ "$owner" = "$session_id" ]; then
    write_lock      # refresh our own claim; keep the lock warm
    exit 0
  fi
  if is_alive "$owner_tx" "$owner_ts"; then
    deny "Blocked: this working directory is locked by another active Claude session.

  workdir: $dir
  owner:   session $owner

Concurrent sessions editing the same workdir clobber each other. Create your
own isolated worktree and develop there instead:

  git worktree add .worktree/<feature-branch> -b <feature-branch>
  cd .worktree/<feature-branch>

(Git enforces one branch per worktree, so pick a fresh branch name.)

If you are certain the other session is dead, remove its lock: $lock
Escape hatch for a deliberate single-operator edit: ALLOW_MAIN_EDIT=1."
  fi
  # Stale or corrupt lock -> fall through to claim below.
fi

# --- Claim (atomic mkdir mutex around the lock write) -----------------------
# Reap an abandoned mutex (a crashed claim that never rmdir'd).
if [ -d "$mutex" ]; then
  mx_mtime="$(stat -c %Y "$mutex" 2>/dev/null || echo 0)"
  if [ $((now - mx_mtime)) -ge "$MUTEX_STALE_SECS" ]; then
    rmdir "$mutex" 2>/dev/null || true
  fi
fi

# Distinguish "mutex already held" (EEXIST -> someone else is mid-claim) from a
# real mkdir failure (permission denied, ENOSPC). On a real failure we must NOT
# fall through to the lost-race allow path — that would let a second session in.
if mkdir "$mutex" 2>/dev/null; then
  trap 'rmdir "$mutex" 2>/dev/null || true' EXIT
  # Double-checked locking: re-read inside the critical section.
  if read_lock && [ "$owner" != "$session_id" ] && is_alive "$owner_tx" "$owner_ts"; then
    deny "Blocked: this working directory was just claimed by another active
Claude session (race). workdir: $dir, owner: session $owner.
Create your own worktree:  git worktree add .worktree/<branch> -b <branch>"
  fi
  write_lock || deny "Blocked: could not write the occupancy lock for $dir
(disk full or permission denied?). Refusing to edit without a lock."
  exit 0
elif [ ! -d "$mutex" ]; then
  # mkdir failed but the mutex dir does NOT exist -> real error, not EEXIST.
  deny "Blocked: cannot create the occupancy-lock mutex for $dir
(permission denied or no space?). Refusing to edit without mutual exclusion.
Escape hatch for a deliberate edit: ALLOW_MAIN_EDIT=1."
fi

# Lost the mutex race to a simultaneous fire: re-read and re-evaluate once.
if read_lock; then
  [ "$owner" = "$session_id" ] && exit 0
  if is_alive "$owner_tx" "$owner_ts"; then
    deny "Blocked: lost the lock race for $dir to another active session ($owner).
Create your own worktree:  git worktree add .worktree/<branch> -b <branch>"
  fi
fi
# No live owner after the race: allow rather than spuriously deny.
exit 0
