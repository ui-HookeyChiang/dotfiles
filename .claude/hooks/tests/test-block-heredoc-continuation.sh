#!/usr/bin/env bash
# Tests for block-heredoc-continuation.sh.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-heredoc-continuation.sh"
pass=0; fail=0

run() {
  local expect="$1" desc="$2" command="$3"
  local json out got
  json="$(jq -n --arg c "$command" '{tool_input:{command:$c}}')"
  out="$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)"
  got="allow"; printf '%s' "$out" | grep -q '"permissionDecision": "deny"' && got="deny"
  if [ "$got" = "$expect" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$desc"
  else fail=$((fail+1)); printf 'FAIL %s (expected %s, got %s)\n' "$desc" "$expect" "$got"; fi
}

run deny "python heredoc then &&" "$(cat <<'EOF'
python3 - <<'PY'
print("hi")
PY && git diff -- path
EOF
)"

run deny "heredoc then pipe" "$(cat <<'EOF'
cat <<'EOF_INNER'
hello
EOF_INNER | wc -l
EOF
)"

run deny "heredoc then semicolon" "$(cat <<'EOF'
python3 - <<'PY'
print("hi")
PY ; git status
EOF
)"

run allow "plain heredoc" "$(cat <<'EOF'
python3 - <<'PY'
print("hi")
PY
EOF
)"

run allow "separate pre-heredoc grouping" "$(cat <<'EOF'
( python3 - <<'PY'
print("hi")
PY
) && git diff -- path
EOF
)"

run allow "no heredoc" "python3 script.py && git diff -- path"

out="$(printf '%s' "$(jq -n --arg c "$(cat <<'EOF'
python3 - <<'PY'
print("hi")
PY && git status
EOF
)" '{tool_input:{command:$c}}')" | ALLOW_HEREDOC_CONTINUATION=1 bash "$HOOK" 2>/dev/null)"
if printf '%s' "$out" | grep -q deny; then fail=$((fail+1)); echo "FAIL escape hatch"
else pass=$((pass+1)); echo "ok   ALLOW_HEREDOC_CONTINUATION=1 escape hatch"; fi

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
