#!/usr/bin/env bash
# SessionEnd hook: release the per-workdir occupancy lock this session owns.
#
# Companion to block-main-edit.sh. On a clean session end, delete the lock at
# <git-dir>/claude-session.lock IFF this session owns it. Best-effort: fires on
# clean exit but NOT on kill -9 / crash / power loss — which is exactly why
# block-main-edit.sh also has a staleness sweep. The two together: SessionEnd
# releases promptly on the common path; staleness reclaims after a crash.
#
# SessionEnd input has no file_path, so resolve the workdir from cwd.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$sid" ] && exit 0
[ -z "$cwd" ] && cwd="${PWD}"

gitdir="$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)" || exit 0
[ -z "$gitdir" ] && exit 0
case "$gitdir" in
  /*) ;;
  *)  gitdir="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir="${cwd}/${gitdir}" ;;
esac
lock="${gitdir}/claude-session.lock"

[ -f "$lock" ] || exit 0
IFS=$'\t' read -r owner _ _ < "$lock"
# Only delete a lock we positively own; a corrupt/empty owner field never
# matches a real session_id, so a malformed lock is left for the staleness
# sweep rather than deleted out from under whoever may actually hold it.
[ -n "$owner" ] && [ "$owner" = "$sid" ] && rm -f "$lock"
exit 0
