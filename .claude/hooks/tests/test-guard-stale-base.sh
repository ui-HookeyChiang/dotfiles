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

# run_raw: like run but returns full output for additional assertions
run_raw() {
  local command="$1"
  local json
  json="$(jq -n --arg c "$command" --arg cwd "$REPO" '{tool_input:{command:$c},cwd:$cwd}')"
  printf '%s' "$json" | bash "$HOOK" 2>/dev/null
}

# run_raw_with_cwd: run_raw with a custom cwd value
run_raw_with_cwd() {
  local command="$1" cwd="$2"
  local json
  json="$(jq -n --arg c "$command" --arg cwd "$cwd" '{tool_input:{command:$c},cwd:$cwd}')"
  printf '%s' "$json" | bash "$HOOK" 2>/dev/null
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

# --- heredoc immunity: body lines must NOT be inspected ---------------------
# bare <<EOF form
run allow "heredoc body with git checkout -b"  "$(printf 'git commit -m "msg" <<EOF\ngit checkout -b new feature-x\nEOF')"
# quoted <<'EOF' form
run allow "heredoc body <<'EOF' form"          "$(printf "git commit -m 'x' <<'EOF'\ngit checkout -b new feature-x\nEOF")"
# quoted <<"EOF" form
run allow 'heredoc body <<"EOF" form'          "$(printf 'git commit -m "x" <<"EOF"\ngit checkout -b new feature-x\nEOF')"
# dash <<-EOF form
run allow "heredoc body <<-EOF form"           "$(printf 'git commit -m "x" <<-EOF\n\tgit checkout -b new feature-x\nEOF')"
# creation BEFORE the heredoc must still be denied
run deny  "creation before heredoc is denied"  "$(printf 'git checkout -b new feature-x\ngit commit -m "x" <<EOF\nbody\nEOF')"

# --- escape hatch -----------------------------------------------------------
out="$(printf '%s' "$(jq -n --arg c 'git checkout -b new feature-x' --arg cwd "$REPO" '{tool_input:{command:$c},cwd:$cwd}')" | ALLOW_STALE_BASE=1 bash "$HOOK" 2>/dev/null)"
if printf '%s' "$out" | grep -q deny; then fail=$((fail+1)); echo "FAIL escape hatch"; else pass=$((pass+1)); echo "ok   ALLOW_STALE_BASE=1 escape hatch"; fi

# ===========================================================================
# NEW TESTS: ticket 2026-07-27-guard-stale-base-hardening
# ===========================================================================

# --- 1. Chained commands: creation in a non-first segment must be denied ----
run deny  "chained: cd && git worktree add from local"  "cd /some/path && git worktree add wt feature-x"
run deny  "chained: echo; git checkout -b from local"   "echo hi; git checkout -b new feature-x"
run deny  "chained: cmd || git branch from local"       "false || git branch new feature-x"
run allow "chained: creation only in echo string"       "echo done; echo 'git checkout -b new feature-x'"

# --- 2. HEAD-based creation: branch behind upstream → deny ------------------
# Set up a repo where local main is behind its upstream
REPO_BEHIND="$TMP/repo-behind"
REMOTE_BEHIND="$TMP/remote-behind.git"
git init -q --bare -b main "$REMOTE_BEHIND"
git init -q -b main "$REPO_BEHIND"
( cd "$REPO_BEHIND"
  git config user.email t@t; git config user.name t
  git remote add origin "$REMOTE_BEHIND"
  echo a > f; git add .; git commit -qm "commit-a"
  git push -qu origin main
  git branch --set-upstream-to=origin/main main
  # advance remote by one commit (without pulling locally)
  git clone -q "$REMOTE_BEHIND" "$TMP/clone-behind"
  cd "$TMP/clone-behind"
  git config user.email t@t; git config user.name t
  echo b > f; git add .; git commit -qm "commit-b"
  git push -q origin main
  # back in REPO_BEHIND: fetch so upstream is visible but local HEAD is behind
  cd "$REPO_BEHIND"
  git fetch -q origin
)

json_behind="$(jq -n --arg c 'git checkout -b new-branch' --arg cwd "$REPO_BEHIND" '{tool_input:{command:$c},cwd:$cwd}')"
out_behind="$(printf '%s' "$json_behind" | bash "$HOOK" 2>/dev/null)"
got_behind="allow"; printf '%s' "$out_behind" | grep -q '"permissionDecision": "deny"' && got_behind="deny"
if [ "$got_behind" = "deny" ]; then
  # Verify behind-count is in the message
  if printf '%s' "$out_behind" | grep -q "behind"; then
    pass=$((pass+1)); echo "ok   HEAD behind upstream → denied with behind-count"
  else
    fail=$((fail+1)); echo "FAIL HEAD behind upstream → denied but no behind-count in message"
  fi
else
  fail=$((fail+1)); echo "FAIL HEAD behind upstream → expected deny, got allow"
fi

# --- 3. HEAD-based creation: no upstream → allow ----------------------------
# REPO has main with no tracking upstream (remote.git doesn't exist yet)
json_noups="$(jq -n --arg c 'git checkout -b new-branch' --arg cwd "$REPO" '{tool_input:{command:$c},cwd:$cwd}')"
out_noups="$(printf '%s' "$json_noups" | bash "$HOOK" 2>/dev/null)"
got_noups="allow"; printf '%s' "$out_noups" | grep -q '"permissionDecision": "deny"' && got_noups="deny"
if [ "$got_noups" = "allow" ]; then pass=$((pass+1)); echo "ok   HEAD no upstream → allowed"
else fail=$((fail+1)); echo "FAIL HEAD no upstream → expected allow, got deny"; fi

# HEAD-based creation: upstream up-to-date → allow
REPO_UPTODATE="$TMP/repo-uptodate"
REMOTE_UPTODATE="$TMP/remote-uptodate.git"
git init -q --bare "$REMOTE_UPTODATE"
git init -q -b main "$REPO_UPTODATE"
( cd "$REPO_UPTODATE"
  git config user.email t@t; git config user.name t
  git remote add origin "$REMOTE_UPTODATE"
  echo a > f; git add .; git commit -qm "commit-a"
  git push -qu origin main
  git branch --set-upstream-to=origin/main main
  git fetch -q origin
)
json_utd="$(jq -n --arg c 'git checkout -b new-branch' --arg cwd "$REPO_UPTODATE" '{tool_input:{command:$c},cwd:$cwd}')"
out_utd="$(printf '%s' "$json_utd" | bash "$HOOK" 2>/dev/null)"
got_utd="allow"; printf '%s' "$out_utd" | grep -q '"permissionDecision": "deny"' && got_utd="deny"
if [ "$got_utd" = "allow" ]; then pass=$((pass+1)); echo "ok   HEAD up-to-date upstream → allowed"
else fail=$((fail+1)); echo "FAIL HEAD up-to-date upstream → expected allow, got deny"; fi

# --- 4. Fetch failure → allowed with additionalContext warning ---------------
# Use a remote that doesn't exist so fetch fails; the base is a remote-prefixed ref
REPO_NOFETCH="$TMP/repo-nofetch"
git init -q -b main "$REPO_NOFETCH"
( cd "$REPO_NOFETCH"
  git config user.email t@t; git config user.name t
  echo x > f; git add .; git commit -qm init
  git remote add origin "file:///nonexistent/path/that/cannot/be/fetched"
)
json_nf="$(jq -n --arg c 'git checkout -b new origin/main' --arg cwd "$REPO_NOFETCH" '{tool_input:{command:$c},cwd:$cwd}')"
out_nf="$(printf '%s' "$json_nf" | bash "$HOOK" 2>/dev/null)"
got_nf_deny="no"; printf '%s' "$out_nf" | grep -q '"permissionDecision": "deny"' && got_nf_deny="yes"
got_nf_warn="no"; printf '%s' "$out_nf" | grep -q "additionalContext" && got_nf_warn="yes"
if [ "$got_nf_deny" = "no" ]; then
  if [ "$got_nf_warn" = "yes" ]; then
    pass=$((pass+1)); echo "ok   fetch failure → allowed with additionalContext warning"
  else
    fail=$((fail+1)); echo "FAIL fetch failure → allowed but no additionalContext warning"
  fi
else
  fail=$((fail+1)); echo "FAIL fetch failure → should allow, not deny"
fi

# --- 5. Bare local ref with SHA == remote counterpart → allowed -------------
REPO_INSYNC="$TMP/repo-insync"
REMOTE_INSYNC="$TMP/remote-insync.git"
git init -q --bare -b main "$REMOTE_INSYNC"
git init -q -b main "$REPO_INSYNC"
( cd "$REPO_INSYNC"
  git config user.email t@t; git config user.name t
  git remote add origin "$REMOTE_INSYNC"
  echo a > f; git add .; git commit -qm "commit-a"
  git push -q origin main
  git branch feature-y
  # Push feature-y so remote has it too
  git push -q origin feature-y
  git fetch -q origin
)
json_insync="$(jq -n --arg c 'git checkout -b new feature-y' --arg cwd "$REPO_INSYNC" '{tool_input:{command:$c},cwd:$cwd}')"
out_insync="$(printf '%s' "$json_insync" | bash "$HOOK" 2>/dev/null)"
got_insync="allow"; printf '%s' "$out_insync" | grep -q '"permissionDecision": "deny"' && got_insync="deny"
if [ "$got_insync" = "allow" ]; then pass=$((pass+1)); echo "ok   bare local == remote SHA → allowed"
else fail=$((fail+1)); echo "FAIL bare local == remote SHA → expected allow, got deny"; fi

# --- 6. Bare local ref behind remote → denied with ahead/behind counts ------
REPO_STALE="$TMP/repo-stale"
REMOTE_STALE="$TMP/remote-stale.git"
git init -q --bare -b main "$REMOTE_STALE"
git init -q -b main "$REPO_STALE"
( cd "$REPO_STALE"
  git config user.email t@t; git config user.name t
  git remote add origin "$REMOTE_STALE"
  echo a > f; git add .; git commit -qm "commit-a"
  git push -q origin main
  git branch feature-z
  git push -q origin feature-z
  # Advance remote feature-z by one commit
  git clone -q "$REMOTE_STALE" "$TMP/clone-stale"
  cd "$TMP/clone-stale"
  git config user.email t@t; git config user.name t
  git checkout -q feature-z
  echo b >> f; git add .; git commit -qm "commit-b"
  git push -q origin feature-z
  # Back in repo: fetch without merging
  cd "$REPO_STALE"
  git fetch -q origin
)
json_stale="$(jq -n --arg c 'git checkout -b new feature-z' --arg cwd "$REPO_STALE" '{tool_input:{command:$c},cwd:$cwd}')"
out_stale="$(printf '%s' "$json_stale" | bash "$HOOK" 2>/dev/null)"
got_stale="allow"; printf '%s' "$out_stale" | grep -q '"permissionDecision": "deny"' && got_stale="deny"
if [ "$got_stale" = "deny" ]; then
  # Verify message has counts and paste-able fix
  has_fix="no"; printf '%s' "$out_stale" | grep -q "git fetch origin" && has_fix="yes"
  has_counts="no"
  ( printf '%s' "$out_stale" | grep -q "behind" || printf '%s' "$out_stale" | grep -q "ahead" ) && has_counts="yes"
  if [ "$has_fix" = "yes" ] && [ "$has_counts" = "yes" ]; then
    pass=$((pass+1)); echo "ok   bare local behind remote → denied with counts and fix"
  else
    fail=$((fail+1)); echo "FAIL bare local behind remote → denied but missing counts or fix (has_fix=$has_fix has_counts=$has_counts)"
  fi
else
  fail=$((fail+1)); echo "FAIL bare local behind remote → expected deny, got allow"
fi

# --- 7. Fetch stamp uses common gitdir (worktrees share stamp) ---------------
REPO_WT="$TMP/repo-wt"
REMOTE_WT="$TMP/remote-wt.git"
git init -q --bare -b main "$REMOTE_WT"
git init -q -b main "$REPO_WT"
( cd "$REPO_WT"
  git config user.email t@t; git config user.name t
  git remote add origin "$REMOTE_WT"
  echo a > f; git add .; git commit -qm init
  git push -q origin main
  git worktree add "$TMP/linked-wt" -b wt-branch
)
# Trigger a fetch via main worktree (origin/main ref)
json_wt1="$(jq -n --arg c 'git checkout -b new origin/main' --arg cwd "$REPO_WT" '{tool_input:{command:$c},cwd:$cwd}')"
printf '%s' "$json_wt1" | bash "$HOOK" 2>/dev/null >/dev/null

# Check that stamp is in common gitdir (not per-worktree .git)
common_gitdir="$REPO_WT/.git"
linked_gitdir="$TMP/linked-wt/.git"
common_stamp="$common_gitdir/.guard-fetch-stamp"
linked_stamp="$linked_gitdir/.guard-fetch-stamp"

if [ -f "$common_stamp" ] && ! [ -f "$linked_stamp" ]; then
  pass=$((pass+1)); echo "ok   fetch stamp in common gitdir, not per-worktree"
elif [ -f "$linked_stamp" ] && ! [ -f "$common_stamp" ]; then
  fail=$((fail+1)); echo "FAIL fetch stamp is in per-worktree gitdir instead of common gitdir"
elif [ -f "$common_stamp" ] && [ -f "$linked_stamp" ]; then
  fail=$((fail+1)); echo "FAIL fetch stamp exists in both common and per-worktree gitdir"
else
  fail=$((fail+1)); echo "FAIL fetch stamp not created in either location (fetch may not have run)"
fi

# --- 8. Empty cwd → fallback to CLAUDE_PROJECT_DIR then PWD -----------------
# Test: empty cwd with CLAUDE_PROJECT_DIR pointing at a valid git repo
json_empty_cwd="$(jq -n --arg c 'git checkout -b new feature-x' '{tool_input:{command:$c},cwd:""}')"
out_empty="$(printf '%s' "$json_empty_cwd" | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" 2>/dev/null)"
got_empty="allow"; printf '%s' "$out_empty" | grep -q '"permissionDecision": "deny"' && got_empty="deny"
if [ "$got_empty" = "deny" ]; then pass=$((pass+1)); echo "ok   empty cwd falls back to CLAUDE_PROJECT_DIR"
else fail=$((fail+1)); echo "FAIL empty cwd with CLAUDE_PROJECT_DIR → expected deny (hook active), got allow (hook skipped)"; fi

# Test: no cwd field at all → falls back to PWD; run in /tmp (non-git) so hook skips gracefully
json_no_cwd="$(jq -n --arg c 'git checkout -b new feature-x' '{tool_input:{command:$c}}')"
out_no_cwd="$(cd /tmp && printf '%s' "$json_no_cwd" | bash "$HOOK" 2>/dev/null)"
ec=$?
# In /tmp (non-git) the hook should exit 0 without denying
if [ $ec -eq 0 ] && ! printf '%s' "$out_no_cwd" | grep -q '"permissionDecision": "deny"'; then
  pass=$((pass+1)); echo "ok   missing cwd field in non-git dir → graceful skip"
else
  fail=$((fail+1)); echo "FAIL missing cwd field in non-git dir → unexpected result (ec=$ec)"
fi

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
