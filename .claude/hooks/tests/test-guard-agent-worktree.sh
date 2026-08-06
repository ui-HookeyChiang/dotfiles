#!/usr/bin/env bash
# Test suite for guard-agent-worktree.sh (PreToolUse) and the agent-map
# writer in subagent-dispatch-inject.sh (SubagentStart).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO_ROOT/hooks/guard-agent-worktree.sh"
DISPATCH="$REPO_ROOT/hooks/subagent-dispatch-inject.sh"

# Source portability helpers
source "$REPO_ROOT/_shared/lib/sh/portability.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROJECT="$TMP/project"
WORKTREE="$PROJECT/.worktrees/ns/task-1"
SIBLING="$PROJECT/.worktrees/ns/task-2"
mkdir -p "$WORKTREE" "$SIBLING"
mkdir -p "$PROJECT/.worktrees/.agent-map"
echo "$WORKTREE" > "$PROJECT/.worktrees/.agent-map/agent-123"

run_guard() {
  local json="$1"
  CLAUDE_PROJECT_DIR="$PROJECT" bash "$GUARD" <<< "$json" 2>/dev/null
}

is_deny() { echo "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }
is_allow() { [ -z "$1" ] || ! is_deny "$1"; }

# ── Guard: file tools ──────────────────────────────────────────────────────

# 1. No agent_id (main session) → allow
out="$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT"'/foo.md"}}')"
is_allow "$out" && pass "1: main session (no agent_id) → allow" || fail "1: main session should allow"

# 2. Unmapped agent → allow
out="$(run_guard '{"agent_id":"unknown-agent","tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT"'/foo.md"}}')"
is_allow "$out" && pass "2: unmapped agent → allow" || fail "2: unmapped agent should allow"

# 3. Repo without .agent-map → allow
out="$(CLAUDE_PROJECT_DIR="$TMP/no-map" bash "$GUARD" <<< '{"agent_id":"agent-123","tool_name":"Edit","tool_input":{"file_path":"/some/file"}}' 2>/dev/null)"
is_allow "$out" && pass "3: no .agent-map dir → allow" || fail "3: no .agent-map should allow"

# 4. In-worktree edit → allow
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Edit","tool_input":{"file_path":"'"$WORKTREE"'/src/main.ts"}}')"
is_allow "$out" && pass "4: in-worktree edit → allow" || fail "4: in-worktree edit should allow"

# 5. Project-root edit → deny
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT"'/src/main.ts"}}')"
is_deny "$out" && pass "5: project-root edit → deny" || fail "5: project-root edit should deny"

# 6. Sibling-worktree edit → deny
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Edit","tool_input":{"file_path":"'"$SIBLING"'/src/main.ts"}}')"
is_deny "$out" && pass "6: sibling-worktree edit → deny" || fail "6: sibling-worktree should deny"

# 7. ../-escape → deny
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Edit","tool_input":{"file_path":"'"$WORKTREE"'/../../escape.md"}}')"
is_deny "$out" && pass "7: ../-escape → deny" || fail "7: ../-escape should deny"

# 8. /tmp write → allow
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Write","tool_input":{"file_path":"/tmp/scratch.txt"}}')"
is_allow "$out" && pass "8: /tmp write → allow" || fail "8: /tmp write should allow"

# 9. Write tool outside worktree → deny (covers MultiEdit/NotebookEdit too)
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Write","tool_input":{"file_path":"'"$PROJECT"'/README.md"}}')"
is_deny "$out" && pass "9: Write outside worktree → deny" || fail "9: Write outside should deny"

# 10. NotebookEdit with notebook_path → deny when outside
out="$(run_guard '{"agent_id":"agent-123","tool_name":"NotebookEdit","tool_input":{"notebook_path":"'"$PROJECT"'/nb.ipynb"}}')"
is_deny "$out" && pass "10: NotebookEdit outside → deny" || fail "10: NotebookEdit outside should deny"

# ── Guard: main-session leg — deny file-tool writes into .worktrees/** ─────

# 20. Main session Edit into .worktrees/** → deny
out="$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$WORKTREE"'/src/main.ts"}}')"
is_deny "$out" && pass "20: main session Edit into worktree → deny" || fail "20: main session Edit into worktree should deny"

# 21. Main session Edit into sibling worktree → deny
out="$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$SIBLING"'/foo.md"}}')"
is_deny "$out" && pass "21: main session Write into sibling worktree → deny" || fail "21: main session Write into sibling should deny"

# 22. Main session Edit into .worktrees/.agent-map → deny (metadata is also protected)
out="$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT"'/.worktrees/.agent-map/some-agent"}}')"
is_deny "$out" && pass "22: main session Edit into .agent-map → deny" || fail "22: main session Edit into .agent-map should deny"

# 23. Main session Edit into project root → allow (not inside .worktrees)
out="$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT"'/foo.md"}}')"
is_allow "$out" && pass "23: main session Edit project root → allow" || fail "23: main session Edit project root should allow"

# 24. Main session Bash into worktree → allow (Bash ungated for main)
out="$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cp result.txt '"$WORKTREE"'/output.txt"},"cwd":"'"$PROJECT"'"}')"
is_allow "$out" && pass "24: main session Bash into worktree → allow" || fail "24: main session Bash into worktree should allow"

# 25. Main session ../-escape into .worktrees → deny
out="$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT"'/src/../.worktrees/ns/task-1/escape.md"}}')"
is_deny "$out" && pass "25: main session ../-escape into worktree → deny" || fail "25: main session ../-escape into worktree should deny"

# 26. ALLOW_MAIN_EDIT=1 bypasses deny
out="$(ALLOW_MAIN_EDIT=1 run_guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$WORKTREE"'/src/main.ts"}}')"
is_allow "$out" && pass "26: ALLOW_MAIN_EDIT=1 bypasses → allow" || fail "26: ALLOW_MAIN_EDIT=1 should bypass"

# 27. Main session /tmp write → allow
out="$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"/tmp/scratch.txt"}}')"
is_allow "$out" && pass "27: main session /tmp write → allow" || fail "27: main session /tmp write should allow"

# ── Guard: Bash git heuristic ──────────────────────────────────────────────

# 11. Out-of-worktree cwd + git push → deny
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Bash","tool_input":{"command":"git push origin main"},"cwd":"'"$PROJECT"'"}')"
is_deny "$out" && pass "11: git push from project root → deny" || fail "11: git push outside should deny"

# 12. Out-of-worktree cwd + git -C <own-worktree> push → allow
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Bash","tool_input":{"command":"git -C '"$WORKTREE"' push origin main"},"cwd":"'"$PROJECT"'"}')"
is_allow "$out" && pass "12: git -C <own-worktree> push → allow" || fail "12: git -C own-worktree should allow"

# 13. Out-of-worktree read-only Bash → allow
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Bash","tool_input":{"command":"git status && ls -la"},"cwd":"'"$PROJECT"'"}')"
is_allow "$out" && pass "13: read-only Bash outside → allow" || fail "13: read-only bash should allow"

# 14. In-worktree cwd: any Bash → allow
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Bash","tool_input":{"command":"git push origin feat/x"},"cwd":"'"$WORKTREE"'"}')"
is_allow "$out" && pass "14: git push from own worktree → allow" || fail "14: in-worktree bash should allow"

# 15. git commit from sibling worktree → deny
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""},"cwd":"'"$SIBLING"'"}')"
is_deny "$out" && pass "15: git commit from sibling → deny" || fail "15: git commit sibling should deny"

# 16. git rebase from outside → deny
out="$(run_guard '{"agent_id":"agent-123","tool_name":"Bash","tool_input":{"command":"git rebase origin/main"},"cwd":"'"$PROJECT"'"}')"
is_deny "$out" && pass "16: git rebase from project root → deny" || fail "16: git rebase outside should deny"

# ── Guard: apply_patch (Codex) ─────────────────────────────────────────────

# 40. apply_patch inside own worktree → allow (mapped subagent)
PATCH_IN='--- a/src/main.ts\n+++ b/.worktrees/ns/task-1/src/main.ts\n@@ -1 +1 @@\n-old\n+new'
out="$(run_guard '{"agent_id":"agent-123","tool_name":"apply_patch","tool_input":{"patch":"'"$PATCH_IN"'"}}')"
is_allow "$out" && pass "40: apply_patch in own worktree → allow" || fail "40: apply_patch in own worktree should allow"

# 41. apply_patch outside worktree → deny (mapped subagent)
PATCH_OUT='--- a/src/main.ts\n+++ b/src/main.ts\n@@ -1 +1 @@\n-old\n+new'
out="$(run_guard '{"agent_id":"agent-123","tool_name":"apply_patch","tool_input":{"patch":"'"$PATCH_OUT"'"}}')"
is_deny "$out" && pass "41: apply_patch outside worktree → deny" || fail "41: apply_patch outside worktree should deny"

# 42. apply_patch into .worktrees/** → deny (main session)
PATCH_WT='--- a/.worktrees/ns/task-1/f.ts\n+++ b/.worktrees/ns/task-1/f.ts\n@@ -1 +1 @@\n-old\n+new'
out="$(run_guard '{"tool_name":"apply_patch","tool_input":{"patch":"'"$PATCH_WT"'"}}')"
is_deny "$out" && pass "42: main session apply_patch into worktree → deny" || fail "42: main session apply_patch into worktree should deny"

# 43. apply_patch to project root → allow (main session)
PATCH_ROOT='--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-old\n+new'
out="$(run_guard '{"tool_name":"apply_patch","tool_input":{"patch":"'"$PATCH_ROOT"'"}}')"
is_allow "$out" && pass "43: main session apply_patch to project root → allow" || fail "43: main session apply_patch to root should allow"

# ── Session claim: concurrent main sessions ───────────────────────────────

CLAIM_PROJECT="$TMP/claim-project"
mkdir -p "$CLAIM_PROJECT/.worktrees"

run_claim_guard() {
  local json="$1"
  shift
  CLAUDE_PROJECT_DIR="$CLAIM_PROJECT" "$@" bash "$GUARD" <<< "$json" 2>/dev/null
}

# 30. First write creates claim file
rm -f "$CLAIM_PROJECT/.worktrees/.session-claim"
out="$(run_claim_guard '{"session_id":"sess-A","tool_name":"Edit","tool_input":{"file_path":"'"$CLAIM_PROJECT"'/foo.md"}}')"
is_allow "$out" || fail "30: first write should allow"
if [ -f "$CLAIM_PROJECT/.worktrees/.session-claim" ]; then
  claimed="$(cat "$CLAIM_PROJECT/.worktrees/.session-claim")"
  [ "$claimed" = "sess-A" ] && pass "30: first write creates claim for sess-A" || fail "30: claim should be sess-A, got $claimed"
else
  fail "30: claim file not created"
fi

# 31. Same session write → allow + heartbeat
sleep 1
mtime_before="$(stat -c %Y "$CLAIM_PROJECT/.worktrees/.session-claim" 2>/dev/null || stat -f %m "$CLAIM_PROJECT/.worktrees/.session-claim")"
out="$(run_claim_guard '{"session_id":"sess-A","tool_name":"Write","tool_input":{"file_path":"'"$CLAIM_PROJECT"'/bar.md"}}')"
mtime_after="$(stat -c %Y "$CLAIM_PROJECT/.worktrees/.session-claim" 2>/dev/null || stat -f %m "$CLAIM_PROJECT/.worktrees/.session-claim")"
is_allow "$out" && [ "$mtime_after" -ge "$mtime_before" ] && pass "31: holder write → allow + heartbeat" || fail "31: holder write should allow and update mtime"

# 32. Different session write → deny
out="$(run_claim_guard '{"session_id":"sess-B","tool_name":"Edit","tool_input":{"file_path":"'"$CLAIM_PROJECT"'/foo.md"}}')"
is_deny "$out" && pass "32: non-holder write → deny" || fail "32: non-holder write should deny"

# 33. Different session read-only Bash → allow (reads never gated)
out="$(run_claim_guard '{"session_id":"sess-B","tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"'"$CLAIM_PROJECT"'"}')"
is_allow "$out" && pass "33: non-holder read-only Bash → allow" || fail "33: non-holder read Bash should allow"

# 34. TTL-expired claim → takeover
touch -d "60 minutes ago" "$CLAIM_PROJECT/.worktrees/.session-claim" 2>/dev/null \
  || touch -A -010000 "$CLAIM_PROJECT/.worktrees/.session-claim" 2>/dev/null
out="$(run_claim_guard '{"session_id":"sess-B","tool_name":"Edit","tool_input":{"file_path":"'"$CLAIM_PROJECT"'/foo.md"}}')"
is_allow "$out" || fail "34: TTL-expired should allow"
claimed="$(cat "$CLAIM_PROJECT/.worktrees/.session-claim")"
[ "$claimed" = "sess-B" ] && pass "34: TTL-expired → takeover by sess-B" || fail "34: claim should be sess-B after TTL, got $claimed"

# 35. ALLOW_SESSION_TAKEOVER=1 → immediate takeover
printf 'sess-C' > "$CLAIM_PROJECT/.worktrees/.session-claim"
touch "$CLAIM_PROJECT/.worktrees/.session-claim"
out="$(ALLOW_SESSION_TAKEOVER=1 run_claim_guard '{"session_id":"sess-D","tool_name":"Edit","tool_input":{"file_path":"'"$CLAIM_PROJECT"'/foo.md"}}')"
is_allow "$out" || fail "35: ALLOW_SESSION_TAKEOVER should allow"
claimed="$(cat "$CLAIM_PROJECT/.worktrees/.session-claim")"
[ "$claimed" = "sess-D" ] && pass "35: ALLOW_SESSION_TAKEOVER=1 → takeover by sess-D" || fail "35: claim should be sess-D, got $claimed"

# 36. No .worktrees dir → no claim logic, allow
NOCLAIM_PROJECT="$TMP/noclaim-project"
mkdir -p "$NOCLAIM_PROJECT"
out="$(CLAUDE_PROJECT_DIR="$NOCLAIM_PROJECT" bash "$GUARD" <<< '{"session_id":"sess-X","tool_name":"Edit","tool_input":{"file_path":"'"$NOCLAIM_PROJECT"'/foo.md"}}' 2>/dev/null)"
is_allow "$out" && pass "36: no .worktrees dir → allow (no claim)" || fail "36: no .worktrees should allow"

# 37. Mapped subagent unaffected by session claim
printf 'sess-Z' > "$CLAIM_PROJECT/.worktrees/.session-claim"
touch "$CLAIM_PROJECT/.worktrees/.session-claim"
mkdir -p "$CLAIM_PROJECT/.worktrees/.agent-map"
WT="$CLAIM_PROJECT/.worktrees/ns/task-1"
mkdir -p "$WT"
echo "$WT" > "$CLAIM_PROJECT/.worktrees/.agent-map/agent-mapped"
out="$(CLAUDE_PROJECT_DIR="$CLAIM_PROJECT" bash "$GUARD" <<< '{"agent_id":"agent-mapped","session_id":"sess-OTHER","tool_name":"Edit","tool_input":{"file_path":"'"$WT"'/file.ts"}}' 2>/dev/null)"
is_allow "$out" && pass "37: mapped subagent → allow (claim irrelevant)" || fail "37: mapped subagent should bypass claim"

# 38. Non-holder write-type git → deny
printf 'sess-A' > "$CLAIM_PROJECT/.worktrees/.session-claim"
touch "$CLAIM_PROJECT/.worktrees/.session-claim"
out="$(run_claim_guard '{"session_id":"sess-B","tool_name":"Bash","tool_input":{"command":"git commit -m test"},"cwd":"'"$CLAIM_PROJECT"'"}')"
is_deny "$out" && pass "38: non-holder write-type git → deny" || fail "38: non-holder git commit should deny"

# ── Session claim: own-worktree exemption (ticket 2026-07-22) ─────────────
# A non-holder session that entered its own git worktree must be able to
# write INSIDE that worktree — the claim protects the SHARED checkout only.

CLAIM_REPO="$TMP/claim-repo"
git init -q "$CLAIM_REPO"
git -C "$CLAIM_REPO" config user.email t@t; git -C "$CLAIM_REPO" config user.name t
mkdir -p "$CLAIM_REPO/.worktrees"
echo x > "$CLAIM_REPO/seed"; git -C "$CLAIM_REPO" add seed; git -C "$CLAIM_REPO" commit -qm seed
OWN_WT="$CLAIM_REPO/.worktrees/mine/task-1"
git -C "$CLAIM_REPO" worktree add -q -b own-wt-branch "$OWN_WT" HEAD
printf 'sess-holder' > "$CLAIM_REPO/.worktrees/.session-claim"
touch "$CLAIM_REPO/.worktrees/.session-claim"

# 44. Non-holder Write INSIDE own worktree → allow
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Write","tool_input":{"file_path":"'"$OWN_WT"'/newfile.md"}}' 2>/dev/null)"
is_allow "$out" && pass "44: non-holder write inside own worktree → allow" || fail "44: own-worktree write should allow (escape hatch)"

# 45. Non-holder Write on SHARED checkout root → still deny
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Edit","tool_input":{"file_path":"'"$CLAIM_REPO"'/seed"}}' 2>/dev/null)"
is_deny "$out" && pass "45: non-holder write on shared checkout → deny" || fail "45: shared-checkout write should still deny"

# 46. Non-holder git -C <own-worktree> commit → allow (also covers WRITE_GIT_RE -C form)
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Bash","tool_input":{"command":"git -C '"$OWN_WT"' commit -m x"}}' 2>/dev/null)"
is_allow "$out" && pass "46: non-holder git -C own-worktree commit → allow" || fail "46: git -C own-worktree commit should allow"

# 47. Non-holder git -C <shared-checkout> commit → deny (regex must catch -C form)
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Bash","tool_input":{"command":"git -C '"$CLAIM_REPO"' commit -m x"}}' 2>/dev/null)"
is_deny "$out" && pass "47: non-holder git -C shared-checkout commit → deny" || fail "47: git -C shared-checkout commit should deny"

# 48. Double `-C`: git uses the LAST path — must resolve to shared checkout → deny
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Bash","tool_input":{"command":"git -C '"$OWN_WT"' -C '"$CLAIM_REPO"' commit -m x"}}' 2>/dev/null)"
is_deny "$out" && pass "48: double -C uses last (shared checkout) → deny" || fail "48: double -C should resolve to last path (shared) and deny"

# ── Session claim: takeover escape hatch reachable from command string ────
# ALLOW_SESSION_TAKEOVER=1 documented as a command-line escape hatch, but the
# guard is a PreToolUse hook — env exported INSIDE the guarded command never
# reaches the hook's own process env. Must also parse it from the command
# string (mirrors ALLOW_BARE_READ handling in block-bare-read.sh).

# 60. Command-string prefix `ALLOW_SESSION_TAKEOVER=1 git ...` → takeover
printf 'sess-holder' > "$CLAIM_REPO/.worktrees/.session-claim"
touch "$CLAIM_REPO/.worktrees/.session-claim"
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-taker","tool_name":"Bash","tool_input":{"command":"ALLOW_SESSION_TAKEOVER=1 git -C '"$CLAIM_REPO"' commit -m x"}}' 2>/dev/null)"
is_allow "$out" || fail "60: command-string ALLOW_SESSION_TAKEOVER=1 prefix should allow"
claimed="$(cat "$CLAIM_REPO/.worktrees/.session-claim")"
[ "$claimed" = "sess-taker" ] && pass "60: command-string ALLOW_SESSION_TAKEOVER=1 prefix → takeover" || fail "60: claim should be sess-taker, got $claimed"

# 61. `export ALLOW_SESSION_TAKEOVER=1; git ...` compound form → takeover
printf 'sess-holder' > "$CLAIM_REPO/.worktrees/.session-claim"
touch "$CLAIM_REPO/.worktrees/.session-claim"
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-taker2","tool_name":"Bash","tool_input":{"command":"export ALLOW_SESSION_TAKEOVER=1; git -C '"$CLAIM_REPO"' commit -m x"}}' 2>/dev/null)"
is_allow "$out" || fail "61: export ALLOW_SESSION_TAKEOVER=1; compound form should allow"
claimed="$(cat "$CLAIM_REPO/.worktrees/.session-claim")"
[ "$claimed" = "sess-taker2" ] && pass "61: export compound form → takeover" || fail "61: claim should be sess-taker2, got $claimed"

# ── Session claim: scope to claimed checkout only ──────────────────────────

# 62. git mutation in an UNRELATED repo → allow despite active claim
UNRELATED_REPO="$TMP/unrelated-repo"
git init -q "$UNRELATED_REPO"
git -C "$UNRELATED_REPO" config user.email t@t; git -C "$UNRELATED_REPO" config user.name t
echo x > "$UNRELATED_REPO/f"; git -C "$UNRELATED_REPO" add f; git -C "$UNRELATED_REPO" commit -qm seed
printf 'sess-holder' > "$CLAIM_REPO/.worktrees/.session-claim"
touch "$CLAIM_REPO/.worktrees/.session-claim"
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Bash","tool_input":{"command":"git -C '"$UNRELATED_REPO"' commit -m x"}}' 2>/dev/null)"
is_allow "$out" && pass "62: git mutation in unrelated repo → allow" || fail "62: unrelated-repo git mutation should allow despite active claim"

# 63. git commit inside a registered worktree (no -C, cwd = worktree) → allow
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"'"$OWN_WT"'"}' 2>/dev/null)"
is_allow "$out" && pass "63: git commit via cwd inside registered worktree → allow" || fail "63: git commit with cwd in registered worktree should allow"

# 64. Plain claimed-checkout mutation still denied (no escape hatch) → deny
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Bash","tool_input":{"command":"git -C '"$CLAIM_REPO"' commit -m x"}}' 2>/dev/null)"
is_deny "$out" && pass "64: plain claimed-checkout mutation → deny" || fail "64: claimed-checkout mutation without escape hatch should still deny"

# ── Leg 4: claim-file deletion audit ───────────────────────────────────────

# 65. bare rm of .worktrees/.session-claim → deny
CLAIM_FILE_PATH="$CLAIM_REPO/.worktrees/.session-claim"
printf 'sess-holder' > "$CLAIM_FILE_PATH"
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"tool_name":"Bash","tool_input":{"command":"rm '"$CLAIM_FILE_PATH"'"},"cwd":"'"$CLAIM_REPO"'"}' 2>/dev/null)"
is_deny "$out" && pass "65: bare rm of .session-claim → deny" || fail "65: rm of session-claim file should deny"

# 66. ALLOW_WORKTREE_LIFECYCLE=1 bypasses claim-file rm deny
out="$(ALLOW_WORKTREE_LIFECYCLE=1 CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"tool_name":"Bash","tool_input":{"command":"rm '"$CLAIM_FILE_PATH"'"},"cwd":"'"$CLAIM_REPO"'"}' 2>/dev/null)"
is_allow "$out" && pass "66: ALLOW_WORKTREE_LIFECYCLE=1 bypasses claim-file rm deny" || fail "66: escape hatch should bypass claim-file rm deny"

# 67. Relative-path rm `.worktrees/.session-claim` with cwd=PROJECT → deny
# (PR #1278 review: realpath -m resolved against the HOOK's own cwd, not
# the guarded command's cwd — this bypassed leg 4c entirely.)
printf 'sess-holder' > "$CLAIM_FILE_PATH"
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"tool_name":"Bash","tool_input":{"command":"rm .worktrees/.session-claim"},"cwd":"'"$CLAIM_REPO"'"}' 2>/dev/null)"
is_deny "$out" && pass "67: relative-path rm .worktrees/.session-claim (cwd=PROJECT) → deny" || fail "67: relative-path rm should deny (bypass regression)"

# 68. Relative-path rm `./.worktrees/.session-claim` with cwd=PROJECT → deny
printf 'sess-holder' > "$CLAIM_FILE_PATH"
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"tool_name":"Bash","tool_input":{"command":"rm ./.worktrees/.session-claim"},"cwd":"'"$CLAIM_REPO"'"}' 2>/dev/null)"
is_deny "$out" && pass "68: relative-path rm ./.worktrees/.session-claim (cwd=PROJECT) → deny" || fail "68: ./-relative rm should deny (bypass regression)"

# 69. ALLOW_SESSION_TAKEOVER=123456 (no boundary after =1) → still denied
# (PR #1278 review: regex lacked a boundary after `=1`, so any numeric
# suffix like `=123456` matched as if it were `=1`.)
printf 'sess-holder' > "$CLAIM_REPO/.worktrees/.session-claim"
touch "$CLAIM_REPO/.worktrees/.session-claim"
out="$(CLAUDE_PROJECT_DIR="$CLAIM_REPO" bash "$GUARD" <<< '{"session_id":"sess-other","tool_name":"Bash","tool_input":{"command":"ALLOW_SESSION_TAKEOVER=123456 git -C '"$CLAIM_REPO"' commit -m x"}}' 2>/dev/null)"
is_deny "$out" && pass "69: ALLOW_SESSION_TAKEOVER=123456 → still deny (no boundary bypass)" || fail "69: =123456 should not satisfy the =1 escape hatch"

# ── Leg 4: Worktree lifecycle guard ────────────────────────────────────────

# Create a project with a real git repo for worktree tests
LIFECYCLE_PROJECT="$TMP/lifecycle-project"
mkdir -p "$LIFECYCLE_PROJECT"
(cd "$LIFECYCLE_PROJECT" && git init -q && git commit --allow-empty -m "init" -q) 2>/dev/null
mkdir -p "$LIFECYCLE_PROJECT/.worktrees/ns/task-1" "$LIFECYCLE_PROJECT/.worktrees/.agent-map"

run_lifecycle() {
  CLAUDE_PROJECT_DIR="$LIFECYCLE_PROJECT" bash "$GUARD" <<< "$1" 2>/dev/null
}

# 50. rm -rf on registered worktree → deny
# First register a worktree so it appears in `git worktree list`
(cd "$LIFECYCLE_PROJECT" && git worktree add .worktrees/ns/real-wt -b test-wt 2>/dev/null) || true
REAL_WT="$(portable_realpath_m "$LIFECYCLE_PROJECT/.worktrees/ns/real-wt")"
out="$(run_lifecycle '{"tool_name":"Bash","tool_input":{"command":"rm -rf '"$REAL_WT"'"},"cwd":"'"$LIFECYCLE_PROJECT"'"}')"
is_deny "$out" && pass "50: rm -rf on registered worktree → deny" || fail "50: should deny rm -rf on registered worktree"

# 51. git worktree remove itself → allow (not rm -rf)
out="$(run_lifecycle '{"tool_name":"Bash","tool_input":{"command":"git worktree remove '"$REAL_WT"'"},"cwd":"'"$LIFECYCLE_PROJECT"'"}')"
is_allow "$out" && pass "51: git worktree remove → allow" || fail "51: git worktree remove should be allowed"

# 52. rm -rf on non-worktree path → allow
out="$(run_lifecycle '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/scratch-dir"},"cwd":"'"$LIFECYCLE_PROJECT"'"}')"
is_allow "$out" && pass "52: rm -rf on non-worktree path → allow" || fail "52: should allow rm -rf outside worktrees"

# 53. Edit into orphan worktree dir (no .git file, not registered) → deny
ORPHAN_DIR="$LIFECYCLE_PROJECT/.worktrees/ns/orphan-task"
mkdir -p "$ORPHAN_DIR"
out="$(run_lifecycle '{"tool_name":"Edit","tool_input":{"file_path":"'"$ORPHAN_DIR"'/src/main.ts"}}')"
is_deny "$out" && pass "53: Edit into orphan worktree dir → deny" || fail "53: should deny edit into orphan dir"

# 54. Edit into registered worktree → allow (mapped subagent)
echo "$REAL_WT" > "$LIFECYCLE_PROJECT/.worktrees/.agent-map/agent-wt"
out="$(CLAUDE_PROJECT_DIR="$LIFECYCLE_PROJECT" bash "$GUARD" <<< '{"agent_id":"agent-wt","tool_name":"Edit","tool_input":{"file_path":"'"$REAL_WT"'/file.ts"}}' 2>/dev/null)"
is_allow "$out" && pass "54: Edit into registered worktree (mapped agent) → allow" || fail "54: should allow mapped agent in registered worktree"

# 55. git add into orphan dir → deny
out="$(run_lifecycle '{"tool_name":"Bash","tool_input":{"command":"git add -f '"$ORPHAN_DIR"'/file.ts"},"cwd":"'"$LIFECYCLE_PROJECT"'"}')"
is_deny "$out" && pass "55: git add into orphan dir → deny" || fail "55: should deny git add into orphan"

# 56. ALLOW_WORKTREE_LIFECYCLE=1 bypasses rm -rf deny
out="$(ALLOW_WORKTREE_LIFECYCLE=1 run_lifecycle '{"tool_name":"Bash","tool_input":{"command":"rm -rf '"$REAL_WT"'"},"cwd":"'"$LIFECYCLE_PROJECT"'"}')"
is_allow "$out" && pass "56: ALLOW_WORKTREE_LIFECYCLE=1 bypasses → allow" || fail "56: escape hatch should bypass"

# Clean up the real worktree
(cd "$LIFECYCLE_PROJECT" && git worktree remove .worktrees/ns/real-wt 2>/dev/null) || true
rmdir "$ORPHAN_DIR" 2>/dev/null || true

# ── Item 1 (leg 4a cwd-relative resolution): relative rm -rf with cwd ──────

# 57. Relative rm -rf .worktrees/ns/task-1 with cwd=PROJECT → deny
# (Without cwd-relative fix, resolves against hook's cwd, bypassing the guard)
ITEM1_PROJECT="$TMP/item1-project"
mkdir -p "$ITEM1_PROJECT"
(cd "$ITEM1_PROJECT" && git init -q && git commit --allow-empty -m "init" -q) 2>/dev/null
mkdir -p "$ITEM1_PROJECT/.worktrees/ns/task-1"
(cd "$ITEM1_PROJECT" && git worktree add .worktrees/ns/task-1 -b task-1-br 2>/dev/null) || true
run_item1() {
  CLAUDE_PROJECT_DIR="$ITEM1_PROJECT" bash "$GUARD" <<< "$1" 2>/dev/null
}
out="$(run_item1 '{"tool_name":"Bash","tool_input":{"command":"rm -rf .worktrees/ns/task-1"},"cwd":"'"$ITEM1_PROJECT"'"}')"
is_deny "$out" && pass "57: relative rm -rf .worktrees/ns/task-1 with cwd=PROJECT → deny" || fail "57: relative rm with cwd should deny (cwd-relative fix)"

# ── Item 3 (realpath -m portability): path normalization with ./ ────────────

# 58. rm with ./ prefix matching normalizes on macOS (portable_realpath_m)
# This test verifies that paths with ./ segments normalize correctly
# on macOS where realpath -m is unavailable.
ITEM3_PROJECT="$TMP/item3-project"
mkdir -p "$ITEM3_PROJECT"
(cd "$ITEM3_PROJECT" && git init -q && git commit --allow-empty -m "init" -q) 2>/dev/null
mkdir -p "$ITEM3_PROJECT/.worktrees/ns/task-1"
(cd "$ITEM3_PROJECT" && git worktree add .worktrees/ns/task-1 -b task-1-br 2>/dev/null) || true
run_item3() {
  CLAUDE_PROJECT_DIR="$ITEM3_PROJECT" bash "$GUARD" <<< "$1" 2>/dev/null
}
out="$(run_item3 '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./.worktrees/ns/task-1"},"cwd":"'"$ITEM3_PROJECT"'"}')"
is_deny "$out" && pass "58: rm with ./ prefix → deny (portable_realpath_m normalizes)" || fail "58: ./- prefixed rm should normalize and deny"

# ── Leg 4a/4c: non-absolute cwd falls back to PROJECT_DIR ─────────────────

# 59. rm -rf with non-absolute cwd (leg 4a) → deny (cwd ignored, resolves against PROJECT_DIR)
out="$(run_item1 '{"tool_name":"Bash","tool_input":{"command":"rm -rf .worktrees/ns/task-1"},"cwd":"foo"}')"
is_deny "$out" && pass "59: rm -rf with relative cwd → deny (leg 4a falls back to PROJECT_DIR)" || fail "59: relative cwd should fall back to PROJECT_DIR and deny"

# 60b. rm with non-absolute cwd (leg 4c) → deny (cwd ignored, resolves against PROJECT_DIR)
CLAIM_4C="$ITEM1_PROJECT/.worktrees/.session-claim"
printf 'sess-holder' > "$CLAIM_4C"
out="$(CLAUDE_PROJECT_DIR="$ITEM1_PROJECT" bash "$GUARD" <<< '{"tool_name":"Bash","tool_input":{"command":"rm .worktrees/.session-claim"},"cwd":"foo"}' 2>/dev/null)"
is_deny "$out" && pass "60b: rm claim-file with relative cwd → deny (leg 4c falls back to PROJECT_DIR)" || fail "60b: relative cwd should fall back to PROJECT_DIR and deny claim-file rm"

# ── SubagentStart: agent-map writer ────────────────────────────────────────

DISPATCH_PROJECT="$TMP/dispatch-project"
mkdir -p "$DISPATCH_PROJECT/.worktrees/feat-x/task-1"

# 17. Prompt with worktree path → writes agent-map entry
dispatch_input='{"agent_id":"agent-abc","subagent_prompt":"Implement in .worktrees/feat-x/task-1 the feature"}'
CLAUDE_PROJECT_DIR="$DISPATCH_PROJECT" bash "$DISPATCH" <<< "$dispatch_input" >/dev/null 2>&1
if [ -f "$DISPATCH_PROJECT/.worktrees/.agent-map/agent-abc" ]; then
  map_val="$(cat "$DISPATCH_PROJECT/.worktrees/.agent-map/agent-abc")"
  expected="$(portable_realpath_m "$DISPATCH_PROJECT/.worktrees/feat-x/task-1")"
  if [ "$map_val" = "$expected" ]; then
    pass "17: dispatch writes agent-map with correct worktree"
  else
    fail "17: agent-map value '$map_val' != expected '$expected'"
  fi
else
  fail "17: agent-map file not created"
fi

# 18. Prompt without worktree path → no map entry
dispatch_input2='{"agent_id":"agent-xyz","subagent_prompt":"Review the code for quality"}'
CLAUDE_PROJECT_DIR="$DISPATCH_PROJECT" bash "$DISPATCH" <<< "$dispatch_input2" >/dev/null 2>&1
if [ ! -f "$DISPATCH_PROJECT/.worktrees/.agent-map/agent-xyz" ]; then
  pass "18: no worktree in prompt → no agent-map entry"
else
  fail "18: agent-map should not exist for unmapped agent"
fi

# 19. No CLAUDE_PROJECT_DIR → no map entry, no crash
dispatch_input3='{"agent_id":"agent-noproj","subagent_prompt":"Work in .worktrees/ns/task-1"}'
CLAUDE_PROJECT_DIR="" bash "$DISPATCH" <<< "$dispatch_input3" >/dev/null 2>&1
pass "19: empty PROJECT_DIR → no crash"

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
