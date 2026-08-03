#!/usr/bin/env bash
# Tests for block-bare-read.sh: deny bare cat/head/tail; allow pipelines,
# redirects, compound commands, heredocs, and tail -f/--follow.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-bare-read.sh"
pass=0; fail=0

# run <expect: allow|deny> <desc> <command-string>
run() {
  local expect="$1" desc="$2" command="$3"
  local json out got
  json="$(jq -n --arg c "$command" '{tool_input:{command:$c}}')"
  out="$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)"
  got="allow"; printf '%s' "$out" | grep -q '"permissionDecision": "deny"' && got="deny"
  if [ "$got" = "$expect" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$desc"
  else fail=$((fail+1)); printf 'FAIL %s (expected %s, got %s)\n' "$desc" "$expect" "$got"; fi
}

# --- MUST deny: bare cat/head/tail -------------------------------------------
run deny  "bare cat"                       "cat file.txt"
run deny  "bare head"                      "head -5 file.txt"
run deny  "bare tail"                      "tail -20 file.txt"
run deny  "absolute path cat"             "/usr/bin/cat file.txt"
run deny  "absolute path head"            "/usr/bin/head -1 file.txt"
run deny  "absolute path tail"            "/usr/bin/tail -n 10 file.txt"
run deny  "cat with flags"                "cat -n file.txt"
run deny  "head with limit"               "head -1 debian/changelog"

# --- MUST allow: pipeline ----------------------------------------------------
run allow "cat pipe grep"                  "cat file | grep foo"
run allow "head pipe sed"                  "head -1 file | sed 's/x/y/'"
run allow "tail pipe wc"                   "tail -5 file | wc -l"

# --- MUST allow: redirect ----------------------------------------------------
run allow "head redirect"                  "head -1 file > out.txt"
run allow "cat append redirect"            "cat file >> out.txt"

# --- MUST allow: tail -f / --follow (monitoring) -----------------------------
run allow "tail -f"                        "tail -f /var/log/syslog"
run allow "tail --follow"                  "tail --follow logfile"
run allow "tail -f with -n"               "tail -n 100 -f /var/log/syslog"

# --- MUST allow: compound / heredoc / subshell --------------------------------
run allow "heredoc"                        "cat << 'EOF'"
run allow "compound &&"                    "echo foo && head file"
run allow "compound ;"                     "head file; echo done"
run allow "subshell \$()"                  "echo \$(cat file)"
run allow "backtick subshell"              "echo \`cat file\`"

# --- MUST allow: non-cat/head/tail commands -----------------------------------
run allow "ls"                             "ls -la"
run allow "grep"                           "grep -r foo ."
run allow "git status"                     "git status"

# --- escape hatch -------------------------------------------------------------
out="$(printf '%s' "$(jq -n --arg c 'cat file.txt' '{tool_input:{command:$c}}')" | ALLOW_BARE_READ=1 bash "$HOOK" 2>/dev/null)"
if printf '%s' "$out" | grep -q deny; then fail=$((fail+1)); echo "FAIL escape hatch"
else pass=$((pass+1)); echo "ok   ALLOW_BARE_READ=1 escape hatch"; fi

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
