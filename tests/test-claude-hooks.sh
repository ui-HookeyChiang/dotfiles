#!/usr/bin/env bash
# tests/test-claude-hooks.sh — TAP-13 suite for the per-workdir occupancy lock.
#
# Covers .claude/hooks/block-main-edit.sh (PreToolUse) and
# .claude/hooks/release-session-lock.sh (SessionEnd):
#   - first session claims a workdir; lock written with 4 TSV fields
#   - same session re-edits (refresh, allow)
#   - second LIVE session is denied and nudged to a worktree
#   - liveness = transcript mtime (NOT pid): a lock whose owner transcript is
#     fresh (or claimed <60s ago) is honored regardless of the recorded pid;
#     a lock whose transcript is stale (> STALE_SECS) is reclaimable regardless
#     of the recorded pid. The host:pid 4th field is debug-only metadata.
#   - cross-host and same-host locks behave identically (pid is never trusted)
#   - v1 (3-field, pidless) locks remain backward compatible
#   - corrupt locks are treated as no-owner (reclaimable), not mis-parsed
#   - non-git paths and missing session_id fail open
#   - release deletes only a lock the session owns
#
# Liveness is intentionally pid-independent. The hook's $PPID is NOT a reliable
# handle on the durable `claude` session: any launcher that wraps the hook in a
# subshell (this repo's CI `bash -e {0}`, and the observed Claude Code runner)
# makes $PPID an ephemeral process that is dead by the next turn — a kill -0 on
# it would mark every lock stale and let concurrent sessions steal each other's
# locks silently. Transcript mtime is the robust signal: a live session appends
# to its transcript on every tool-use. Tests hand-craft lock files (controlled
# host:pid) to prove the pid is ignored either way.
#
# Output: TAP-13. Exit 0 on all pass, non-zero otherwise.

# NOT -e: this suite self-manages failures via counters, and many checks
# legitimately use the non-zero return of a command (is_deny, grep -q) as data.
# CI invokes scripts as `bash -e {0}`, so explicitly disable errexit here.
set +e
set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
BLOCK="$repo_root/.claude/hooks/block-main-edit.sh"
RELEASE="$repo_root/.claude/hooks/release-session-lock.sh"

echo "TAP version 13"
N=0; FAILS=0
pass(){ N=$((N+1)); echo "ok $N - $1"; }
fail(){ N=$((N+1)); FAILS=$((FAILS+1)); echo "not ok $N - $1"; }
chk(){ if [ "$1" = pass ]; then pass "$2"; else fail "$2"; fi; }

command -v jq >/dev/null 2>&1 || { echo "1..0 # SKIP jq not installed"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "1..0 # SKIP git not installed"; exit 0; }

HOST="${HOSTNAME:-$(hostname 2>/dev/null || echo unknown)}"
# Allow output is empty (hook exits 0 silently); deny output is JSON. Guard the
# empty case explicitly — jq's exit code on empty stdin differs across versions
# (1.6 vs 1.7), so never let jq adjudicate "no input". For real JSON, use
# `// empty` + a value test that is exit-code-stable across jq versions.
is_deny(){
  [ -n "$1" ] || return 1   # empty == allow
  [ "$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = deny ]
}
inp(){ jq -nc --arg s "$1" --arg f "$2" --arg t "$3" \
  '{session_id:$s,transcript_path:$t,tool_input:{file_path:$f}}'; }
run_block(){ "$BLOCK" <<<"$(inp "$1" "$2" "$3")"; }  # echoes hook stdout

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO" "$TXA" "$TXB" "$NONGIT" 2>/dev/null' EXIT
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
echo x > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -qm init
LOCK="$REPO/.git/claude-session.lock"
TXA="$(mktemp)"; TXB="$(mktemp)"; touch "$TXA" "$TXB"
now(){ date +%s; }
stale(){ echo $(( $(date +%s) - 99999 )); }
# Portable "set this file's mtime ~28h into the past" (well past STALE_SECS).
# GNU touch accepts `-d @<epoch>`; BSD touch does not, but both accept
# `-t [[CC]YY]MMDDhhmm[.ss]`. Use a fixed old wall-clock stamp for BSD.
backdate(){  # $1 = path
  touch -d "@$(stale)" "$1" 2>/dev/null || touch -t 202001010000 "$1"
}

# Hand-write a lock: owner transcript epoch host:pid
wl(){ printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" > "$LOCK"; }

# 1: first claim allowed + 4-field lock
out="$(run_block sessA "$REPO/f" "$TXA")"
if ! is_deny "$out" && [ -f "$LOCK" ] && [ "$(awk -F'\t' '{print NF}' "$LOCK")" = 4 ]; then
  chk pass "first claim allowed, 4-field lock written"
else chk fail "first claim allowed, 4-field lock written"; fi

# 2: same session refresh
out="$(run_block sessA "$REPO/f" "$TXA")"
is_deny "$out" && chk fail "same session re-edit allowed" || chk pass "same session re-edit allowed"

# 3: same-host pid is NOT trusted — a DEAD pid with a FRESH transcript is
# still honored (deny). Liveness comes from transcript mtime, not kill -0, so
# the (irrelevant) dead pid must not grant a reclaim while the owner is active.
touch "$TXA"
wl sessA "$TXA" "$(stale)" "${HOST}:999999"
out="$(run_block sessB "$REPO/f" "$TXB")"
is_deny "$out" && chk pass "dead same-host pid ignored; fresh transcript holds lock" \
               || chk fail "dead same-host pid ignored; fresh transcript holds lock"

# 4: same-host pid is NOT trusted — a LIVE pid with a STALE transcript is
# reclaimable. A long-quiet session (no transcript writes past STALE_SECS) is
# treated as gone regardless of its process still being alive.
sleep 300 & DURABLE=$!
backdate "$TXB"
wl sessA "$TXB" "$(stale)" "${HOST}:${DURABLE}"
out="$(run_block sessC "$REPO/f" "$(mktemp)")"
if ! is_deny "$out" && grep -q '^sessC	' "$LOCK"; then
  chk pass "live same-host pid ignored; stale transcript reclaimed"
else chk fail "live same-host pid ignored; stale transcript reclaimed"; fi
kill "$DURABLE" 2>/dev/null; wait "$DURABLE" 2>/dev/null

# 5: deny message nudges to a worktree
sleep 300 & DURABLE=$!
wl sessA "$TXA" "$(now)" "${HOST}:${DURABLE}"
out="$(run_block sessB "$REPO/f" "$TXB")"
printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' \
  | grep -q 'git worktree add' && chk pass "deny message nudges to a worktree" \
                               || chk fail "deny message nudges to a worktree"
kill "$DURABLE" 2>/dev/null; wait "$DURABLE" 2>/dev/null

# 6: cross-host stale lock reclaimed via mtime
backdate "$TXA"
wl sessA "$TXA" "$(stale)" "otherhost-xyz:4242"
out="$(run_block sessB "$REPO/f" "$TXB")"
if ! is_deny "$out" && grep -q '^sessB	' "$LOCK"; then
  chk pass "cross-host stale lock reclaimed via mtime"
else chk fail "cross-host stale lock reclaimed via mtime"; fi

# 7: cross-host FRESH transcript denied
touch "$TXA"
wl sessA "$TXA" "$(stale)" "otherhost-xyz:4242"
out="$(run_block sessB "$REPO/f" "$TXB")"
is_deny "$out" && chk pass "cross-host fresh-transcript denied" \
               || chk fail "cross-host fresh-transcript denied"

# 8: v1 3-field lock honored (live by mtime -> deny)
touch "$TXA"
printf 'sessA\t%s\t%s\n' "$TXA" "$(now)" > "$LOCK"
out="$(run_block sessB "$REPO/f" "$TXB")"
is_deny "$out" && chk pass "v1 pidless lock honored via mtime (deny live)" \
               || chk fail "v1 pidless lock honored via mtime (deny live)"

# 9: v1 stale lock reclaimed
backdate "$TXA"
printf 'sessA\t%s\t%s\n' "$TXA" "$(stale)" > "$LOCK"
out="$(run_block sessB "$REPO/f" "$TXB")"
if ! is_deny "$out" && grep -q '^sessB	' "$LOCK"; then
  chk pass "v1 stale lock reclaimed"
else chk fail "v1 stale lock reclaimed"; fi

# 10: corrupt lock (1 field) reclaimable
printf 'garbage_no_tabs\n' > "$LOCK"
out="$(run_block sessZ "$REPO/f" "$(mktemp)")"
if ! is_deny "$out" && grep -q '^sessZ	' "$LOCK"; then
  chk pass "corrupt lock reclaimed by new session"
else chk fail "corrupt lock reclaimed by new session"; fi

# 11: non-git path fails open
NONGIT="$(mktemp -d)"
out="$(run_block sessA "$NONGIT/x" "$TXA")"
is_deny "$out" && chk fail "non-git path allowed (fail open)" \
               || chk pass "non-git path allowed (fail open)"

# 12: missing session_id fails open
out="$("$BLOCK" <<<"$(jq -nc --arg f "$REPO/f" '{tool_input:{file_path:$f}}')")"
is_deny "$out" && chk fail "missing session_id allowed (fail open)" \
               || chk pass "missing session_id allowed (fail open)"

# 13: detached HEAD still protected (lock keyed on git-dir, not branch)
git -C "$REPO" checkout -q --detach HEAD
sleep 300 & DURABLE=$!
wl sessA "$TXA" "$(now)" "${HOST}:${DURABLE}"
out="$(run_block sessB "$REPO/f" "$TXB")"
is_deny "$out" && chk pass "detached HEAD: second session denied" \
               || chk fail "detached HEAD: second session denied"
kill "$DURABLE" 2>/dev/null; wait "$DURABLE" 2>/dev/null
git -C "$REPO" checkout -q -

# 14: release by owner removes the lock
wl sessA "$TXA" "$(now)" "${HOST}:$$"
echo "{\"session_id\":\"sessA\",\"cwd\":\"$REPO\"}" | "$RELEASE"
[ -f "$LOCK" ] && chk fail "owner release removes lock" || chk pass "owner release removes lock"

# 15: release by non-owner is a no-op
wl sessA "$TXA" "$(now)" "${HOST}:$$"
echo "{\"session_id\":\"sessB\",\"cwd\":\"$REPO\"}" | "$RELEASE"
[ -f "$LOCK" ] && chk pass "non-owner release is a no-op" || chk fail "non-owner release is a no-op"

# 16: NotebookEdit notebook_path field resolves
rm -f "$LOCK"
out="$("$BLOCK" <<<"$(jq -nc --arg s sessA --arg f "$REPO/n.ipynb" --arg t "$TXA" \
  '{session_id:$s,transcript_path:$t,tool_input:{notebook_path:$f}}')")"
if ! is_deny "$out" && [ -f "$LOCK" ]; then chk pass "NotebookEdit notebook_path resolves"
else chk fail "NotebookEdit notebook_path resolves"; fi

# 17: ALLOW_MAIN_EDIT escape hatch
sleep 300 & DURABLE=$!
wl sessA "$TXA" "$(now)" "${HOST}:${DURABLE}"
out="$(ALLOW_MAIN_EDIT=1 "$BLOCK" <<<"$(inp sessB "$REPO/f" "$TXB")")"
is_deny "$out" && chk fail "ALLOW_MAIN_EDIT bypasses lock" \
               || chk pass "ALLOW_MAIN_EDIT bypasses lock"
kill "$DURABLE" 2>/dev/null; wait "$DURABLE" 2>/dev/null

echo "1..$N"
[ "$FAILS" -eq 0 ]
