#!/usr/bin/env bash
# Tests for block-bare-read.sh: deny bare cat/head/tail, grep/rg, find (pure search),
# sed (extract-only), awk (trivial); allow pipelines, redirects, compound commands,
# heredocs, tail -f/--follow, and prefix-stripped variants.
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

# ============================================================================
# CAT / HEAD / TAIL
# ============================================================================
run deny  "bare cat"                       "cat file.txt"
run deny  "bare head"                      "head -5 file.txt"
run deny  "bare tail"                      "tail -20 file.txt"
run deny  "absolute path cat"             "/usr/bin/cat file.txt"
run deny  "absolute path head"            "/usr/bin/head -1 file.txt"
run deny  "absolute path tail"            "/usr/bin/tail -n 10 file.txt"
run deny  "cat with flags"                "cat -n file.txt"
run deny  "head with limit"               "head -1 debian/changelog"

# ============================================================================
# GREP / RG (ALL BARE FORMS DENIED)
# ============================================================================
run deny  "bare grep"                      "grep foo file.txt"
run deny  "grep with pattern"              "grep -r error ."
run deny  "grep with flags"                "grep -i search file"
run deny  "bare rg"                        "rg pattern file"
run deny  "rg with flags"                  "rg -i search ."

# ============================================================================
# FIND (PURE SEARCH DENIED; WITH ACTION/PREDICATE ALLOWED)
# ============================================================================
# Deny: pure search (no action, no time/size predicate)
run deny  "find with -name only"           "find . -name '*.txt'"
run deny  "find with -iname only"          "find . -iname '*.txt'"
run deny  "find with -path only"           "find . -path '*/src/*.js'"
run deny  "find with -type only"           "find . -type f"

# Allow: with action flag
run allow "find with -exec"                "find . -name '*.txt' -exec cat {} \\;"
run allow "find with -execdir"             "find . -name '*.js' -execdir grep foo {} \\;"
run allow "find with -delete"              "find . -name '*.tmp' -delete"
run allow "find with -ok"                  "find . -name '*.bak' -ok rm {} \\;"

# Allow: with time/size predicates
run allow "find with -mtime"               "find . -mtime -1"
run allow "find with -newer"               "find . -newer reference.txt"
run allow "find with -size"                "find . -size +10M"
run allow "find with -atime"               "find . -atime +30"

# ============================================================================
# SED (EXTRACT-ONLY DENIED WITH -n; TRANSFORMS ALLOWED)
# ============================================================================
# Deny: sed -n (extract-only line selection)
run deny  "sed -n 'Np' extract"            "sed -n '5p' file.txt"
run deny  "sed -n 'N,Mp' range"            "sed -n '10,20p' file.txt"

# Allow: sed transformations (without -n or with other flags)
run allow "sed substitution"               "sed 's/foo/bar/' file.txt"
run allow "sed with -i"                    "sed -i 's/a/b/' file.txt"
run allow "sed -e multiple"                "sed -e 's/x/y/' file.txt"

# ============================================================================
# AWK (TRIVIAL FORMS DENIED; REAL PROCESSING ALLOWED)
# ============================================================================
# Deny: trivial forms
run deny  "awk 1 passthrough"              "awk 1 file.txt"
run deny  "awk '{print}' trivial"          "awk '{print}' file.txt"
run deny  "awk 'NR<=5' range"              "awk 'NR<=5' file.txt"

# Allow: actual data processing
run allow "awk sum calculation"            "awk '{sum+=\$1}END{print sum}' file.txt"
run allow "awk field extraction"           "awk '{print \$1, \$3}' file.txt"
run allow "awk with -F"                    "awk -F: '{print \$1}' /etc/passwd"

# ============================================================================
# PREFIX STRIPPING (env, command, builtin, nice, nohup, timeout, backslash)
# ============================================================================
# env prefix
run deny  "env cat file"                   "env cat file.txt"
run deny  "env -i cat file"                "env -i cat file.txt"
run deny  "env VAR=val cat"                "env VAR=value cat file.txt"
# REGRESSION: quote-aware env parsing (issue #1)
run deny  "env VAR quoted spaces"          "env VAR=\"a b\" cat file.txt"
run deny  "env -S quoted multi"            "env -S \"FOO=bar BAZ=qux\" cat file.txt"

# command builtin prefix
run deny  "command cat"                    "command cat file.txt"
run deny  "builtin cat"                    "builtin cat file.txt"

# nice / nohup / timeout
run deny  "nice cat"                       "nice cat file.txt"
run deny  "nohup cat"                      "nohup cat file.txt"
run deny  "timeout basic"                  "timeout 10 cat file.txt"
# REGRESSION: timeout with flags (issue #2)
run deny  "timeout -s KILL"                "timeout -s KILL 5 cat file.txt"
run deny  "timeout --signal=KILL"          "timeout --signal=KILL 5 cat file.txt"

# backslash prefix
run deny  "\\cat escape"                   "\\cat file.txt"

# ============================================================================
# BASH -c / SH -c UNWRAPPING
# ============================================================================
run deny  "bash -c cat"                    "bash -c 'cat file.txt'"
run deny  "bash -c grep"                   "bash -c 'grep pattern file'"
run deny  "sh -c cat"                      "sh -c 'cat file.txt'"
# REGRESSION: bash -c with escaped/nested quotes (reviewer nit, document behavior)
# Current behavior: permissive-miss if bash -c body has unbalanced quotes
run deny  "bash -c simple double quote"    "bash -c \"cat 'file.txt'\""

# ============================================================================
# PIPELINES (ALLOW)
# ============================================================================
run allow "cat pipe grep"                  "cat file | grep foo"
run allow "head pipe sed"                  "head -1 file | sed 's/x/y/'"
run allow "tail pipe wc"                   "tail -5 file | wc -l"
run allow "grep pipe sort"                 "grep error log | sort"

# ============================================================================
# REDIRECTS (ALLOW)
# ============================================================================
run allow "head redirect >"                "head -1 file > out.txt"
run allow "cat redirect >>"                "cat file >> out.txt"
run allow "sed redirect"                   "sed 's/a/b/' file > out.txt"

# ============================================================================
# COMPOUND / HEREDOC / SUBSHELL (ALLOW)
# ============================================================================
run allow "heredoc"                        "cat << 'EOF'"
run allow "compound &&"                    "echo foo && head file"
run allow "compound ;"                     "head file; echo done"
run allow "subshell \$()"                  "echo \$(cat file)"
run allow "backtick subshell"              "echo \`cat file\`"

# ============================================================================
# TAIL -f / --follow (ALLOW MONITORING)
# ============================================================================
run allow "tail -f"                        "tail -f /var/log/syslog"
run allow "tail --follow"                  "tail --follow logfile"
run allow "tail -f with -n"               "tail -n 100 -f /var/log/syslog"

# ============================================================================
# NON-BLOCKED COMMANDS (ALLOW)
# ============================================================================
run allow "ls"                             "ls -la"
run allow "wc"                             "wc -l file.txt"
run allow "nl"                             "nl file.txt"
run allow "tac"                            "tac file.txt"
run allow "git show"                       "git show HEAD:file.txt"
run allow "python read"                    "python -c 'open(\"file\").read()'"
run allow "node read"                      "node -e 'console.log(fs.readFileSync(\"file\"))'"

# ============================================================================
# FALSE-POSITIVE CHECKS (EDGE CASES)
# ============================================================================
# These should all ALLOW (tricky edge cases where we must not false-deny)
# Note: grep is now fully denied bare, so old edge cases flip to DENY
run allow "awk custom awk code"            "awk '{if(NR>5) print}' file"
run allow "sed complex transform"          "sed -e 's/^/prefix:/' file"
run allow "find with -name and -exec"      "find . -name '*.txt' -exec wc {} \\;"
run allow "pipeline with grep"             "cat file | grep -v '^#'"

# ============================================================================
# ESCAPE HATCH (ALLOW_BARE_READ=1)
# ============================================================================
out="$(printf '%s' "$(jq -n --arg c 'cat file.txt' '{tool_input:{command:$c}}')" | ALLOW_BARE_READ=1 bash "$HOOK" 2>/dev/null)"
if printf '%s' "$out" | grep -q deny; then fail=$((fail+1)); echo "FAIL escape hatch cat"
else pass=$((pass+1)); echo "ok   ALLOW_BARE_READ=1 escape hatch"; fi

out="$(printf '%s' "$(jq -n --arg c 'grep foo file' '{tool_input:{command:$c}}')" | ALLOW_BARE_READ=1 bash "$HOOK" 2>/dev/null)"
if printf '%s' "$out" | grep -q deny; then fail=$((fail+1)); echo "FAIL escape hatch grep"
else pass=$((pass+1)); echo "ok   ALLOW_BARE_READ=1 escape hatch grep"; fi

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
