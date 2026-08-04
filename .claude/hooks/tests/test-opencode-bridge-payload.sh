#!/usr/bin/env bash
# test-opencode-bridge-payload.sh — regression suite for the payload CONTRACT
# the OpenCode plugin depends on: block-bare-read.sh must parse
# {tool_input:{command:"..."}} and emit permissionDecision JSON.
#
# This does NOT execute skill-dev-hooks.ts. Plugin↔hook linkage is verified
# by test-opencode-manifest-agreement.sh (name agreement) and the real-CLI
# e2e (opencode run; see hooks/opencode/README.md). What this suite pins is
# the hook side of the contract, with wrapper/pipeline cases beyond the
# core suite in test-block-bare-read.sh.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-bare-read.sh"
pass=0; fail=0

# run <expect: allow|deny> <desc> <command-string>
run() {
  local expect="$1" desc="$2" command="$3"
  local json out got
  # Simulate OpenCode plugin payload
  json="$(jq -n --arg c "$command" '{tool_input:{command:$c}}')"
  out="$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)"
  got="allow"; printf '%s' "$out" | grep -q '"permissionDecision": "deny"' && got="deny"
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1)); printf 'ok   %s\n' "$desc"
  else
    fail=$((fail+1)); printf 'FAIL %s (expected %s, got %s)\n' "$desc" "$expect" "$got"
  fi
}

echo "=== Deny cases: bare cat/head/tail (→ Read tool) ==="
run deny  "bare cat file"                       "cat file.txt"
run deny  "bare head -5"                        "head -5 file.txt"
run deny  "bare tail without -f"                "tail -20 file.txt"
run deny  "absolute path cat"                   "/bin/cat file.txt"

echo ""
echo "=== Deny cases: bare grep/rg (→ Grep tool) ==="
run deny  "bare grep"                           "grep foo file.txt"
run deny  "bare rg"                             "rg pattern src/"
run deny  "grep with flags"                     "grep -r foo ."

echo ""
echo "=== Deny cases: find pure-search (→ Glob tool) ==="
run deny  "find -name only"                     "find . -name '*.txt'"
run deny  "find -path only"                     "find src -path '*test*'"

echo ""
echo "=== Deny cases: sed extract-only (→ Read tool) ==="
run deny  "sed -n for extraction"               "sed -n '1,5p' file.txt"
run deny  "sed -n single line"                  "sed -n '10p' file.txt"

echo ""
echo "=== Allow cases: find with actions (Bash legitimately needed) ==="
run allow "find -exec"                          "find . -name '*.log' -exec rm {} \\;"
run allow "find -delete"                        "find . -name '*.bak' -delete"
run allow "find -ok"                            "find . -type f -ok rm {} \\;"

echo ""
echo "=== Allow cases: find with time predicates (Bash needed) ==="
run allow "find -mtime"                         "find . -mtime -1"
run allow "find -newer"                         "find . -newer file.txt"

echo ""
echo "=== Allow cases: pipelines ==="
run allow "grep piped to cat"                   "grep -r foo . | cat file"
run allow "cat piped to wc"                     "cat file | wc -l"
run allow "find piped to head"                  "find . -type f | head -10"

echo ""
echo "=== Allow cases: redirects ==="
run allow "cat with output redirect"            "cat file > out.txt"
run allow "head with append redirect"           "head -5 file >> out.txt"

echo ""
echo "=== Allow cases: tail -f/--follow (monitoring) ==="
run allow "tail -f monitoring"                  "tail -f /var/log/app.log"
run allow "tail --follow"                       "tail --follow /var/log/syslog"

echo ""
echo "=== Allow cases: sed transformations (Bash needed) ==="
run allow "sed with transformation"             "sed 's/old/new/g' file.txt"
run allow "sed without -n"                      "sed '1d' file.txt"

echo ""
echo "=== Allow cases: awk non-trivial (Bash needed) ==="
run allow "awk with processing"                 "awk -F: '{print \$1}' passwd"
run allow "awk with condition"                  "awk 'NF > 2' file.txt"

echo ""
echo "=== Allow cases: compound/heredoc ==="
run allow "compound with &&"                    "cat file && echo done"
run allow "compound with ;"                     "cat file; ls"
run allow "subshell with \$()"                  "echo \$(cat file)"
run allow "backtick subshell"                   "echo \`cat file\`"
run allow "heredoc cat"                         "cat << 'EOF'"

echo ""
echo "=== Deny cases: wrappers around blocked commands ==="
run deny  "env with VAR=value + cat"            "env DEBUG=1 cat file"
run deny  "command prefix + cat"                "command cat file"
run deny  "timeout wrapper + cat"               "timeout 10 cat file"

echo ""
echo "=== Allow cases: wrappers around allowed commands ==="
run allow "env with VAR=value + ls"             "env DEBUG=1 ls -la"
run allow "command prefix + git"                "command git status"
run allow "timeout wrapper + grep piped"        "timeout 10 grep foo file | wc -l"

echo ""
echo "=== Allow cases: other commands ==="
run allow "ls"                                  "ls -la"
run allow "git status"                          "git status"
run allow "ps aux"                              "ps aux | grep node"

echo ""
echo "=== Escape hatch: ALLOW_BARE_READ=1 ==="
json="$(jq -n --arg c 'cat file.txt' '{tool_input:{command:$c}}')"
out="$(printf '%s' "$json" | ALLOW_BARE_READ=1 bash "$HOOK" 2>/dev/null)"
if printf '%s' "$out" | grep -q '"permissionDecision": "deny"'; then
  fail=$((fail+1)); echo "FAIL escape hatch (should allow with ALLOW_BARE_READ=1)"
else
  pass=$((pass+1)); echo "ok   ALLOW_BARE_READ=1 escape hatch"
fi

echo ""
echo "=== Pass/Fail Summary ==="
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
