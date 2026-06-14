#!/usr/bin/env bash
# warn-stale-main.sh — UserPromptSubmit hook.
# Warns when the conversation's view of the code may be stale vs main:
#   (a) HEAD is behind its upstream (someone pushed; you fetched but not pulled)
#   (b) HEAD moved since the last warning (a pull / checkout landed mid-session)
# Advisory only: injects a re-read nudge via stdout, never blocks, never touches
# git state. The "behind" signal reuses the statusline's rev-list logic and is
# only as fresh as the last `git fetch` (git has no remote truth without one).
set -euo pipefail

cwd="$(jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0   # not a repo → silent no-op

gitdir="$(git rev-parse --git-dir)"
stamp="$gitdir/.claude-session-head"
now="$(git rev-parse HEAD 2>/dev/null || echo none)"

# (a) behind upstream — stateless, self-clears on pull. Same one-liner as the
# statusline's behind-count (statusline-command.sh: git rev-list --count HEAD..@{upstream}).
behind=0
if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  behind="$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)"
fi

# (b) HEAD moved since last warning — needs the stamp to fire ONCE per move,
# not every prompt.
moved=""
prev=""
[[ -f "$stamp" ]] && prev="$(cat "$stamp" 2>/dev/null || true)"
[[ -n "$prev" && "$prev" != "$now" ]] && moved="HEAD moved ${prev:0:8}→${now:0:8}"

msg=""
[[ "$behind" -gt 0 ]] && msg+="main ${behind} commit(s) ahead of HEAD (as of last fetch). "
[[ -n "$moved" ]] && msg+="${moved}. "

if [[ -n "$msg" ]]; then
  echo "⚠ Stale-code guard: ${msg}Re-read any file from disk before editing or quoting line numbers."
  git rev-parse HEAD > "$stamp" 2>/dev/null || true   # advance: warn once per move
fi

# Seed the stamp on the first prompt of a session if it is missing.
[[ -f "$stamp" ]] || git rev-parse HEAD > "$stamp" 2>/dev/null || true
exit 0
