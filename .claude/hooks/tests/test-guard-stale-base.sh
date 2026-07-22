#!/usr/bin/env bash
# Tests for guard-stale-base.sh: deny branch-creation from a stale LOCAL
# start-point; allow remote/tag/SHA start-points; do NOT touch non-creation
# commands (deletion/listing/rename), no-start-point creation, or text inside
# heredocs / redirections.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/guard-stale-base.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

REPO="$TMP/repo"
git init -q -b main "$REPO"
( cd "$REPO"
  git config user.email t@t; git config user.name t
  echo x > f; git add .; git commit -qm init
  git branch feature-x
  git tag -a v1.0 -m v1.0
  git remote add origin "$TMP/remote.git" )

# run <expect: allow|deny> <desc> <command-string>
run() {
  local expect="$1" desc="$2" command="$3"
  local json out got
  json="$(jq -n --arg c "$command" --arg cwd "$REPO" '{tool_input:{command:$c},cwd:$cwd}')"
  out="$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)"
  got="allow"; printf '%s' "$out" | grep -q '"permissionDecision": "deny"' && got="deny"
  if [ "$got" = "$expect" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$desc"
  else fail=$((fail+1)); printf 'FAIL %s (expected %s, got %s)\n' "$desc" "$expect" "$got"; fi
}

# --- true positives: MUST still deny (stale local start-point) --------------
run deny  "checkout -b from local branch"      "git checkout -b new feature-x"
run deny  "switch -c from local branch"        "git switch -c new feature-x"
run deny  "branch <name> <local-start>"        "git branch new feature-x"
run deny  "worktree add from local branch"     "git worktree add ../wt feature-x"
run deny  "worktree add -b from local branch"  "git worktree add ../wt -b new feature-x"

# --- allowed start-points ---------------------------------------------------
run allow "checkout -b from origin/ ref"       "git checkout -b new origin/main"
run allow "checkout -b from tag"               "git checkout -b new v1.0"
run allow "checkout -b from SHA"               "git checkout -b new 0123abc"

# --- the 4 documented FALSE POSITIVES: MUST now allow -----------------------
run allow "branch -D deletion (two branches)"  "git branch -D feature-x other"
run allow "branch --list pattern"              "git branch --list 'feat/*'"
run allow "branch -d single"                   "git branch -d feature-x"
run allow "branch -m rename"                   "git branch -m old new"
run allow "commit -m body containing 'in'"     "git commit -m 'fix bug in the parser code'"
run allow "switch -c with redirect, no sp"     "git switch -c new 2>&1 | tail -1"
run allow "checkout -b no start-point"         "git checkout -b new"
run allow "switch -c no start-point"           "git switch -c new"
run allow "branch <name> no start-point"       "git branch new"

# --- anchoring: heredoc / later subcommand must not trip --------------------
run allow "later git branch in && chain"       "git status && echo 'git branch x feature-x'"
run deny  "real creation before ; separator"   "git checkout -b new feature-x; echo done"

# --- escape hatch -----------------------------------------------------------
out="$(printf '%s' "$(jq -n --arg c 'git checkout -b new feature-x' --arg cwd "$REPO" '{tool_input:{command:$c},cwd:$cwd}')" | ALLOW_STALE_BASE=1 bash "$HOOK" 2>/dev/null)"
if printf '%s' "$out" | grep -q deny; then fail=$((fail+1)); echo "FAIL escape hatch"; else pass=$((pass+1)); echo "ok   ALLOW_STALE_BASE=1 escape hatch"; fi

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
