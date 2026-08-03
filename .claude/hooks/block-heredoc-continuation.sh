#!/usr/bin/env bash
# block-heredoc-continuation.sh — deny heredoc terminators with trailing shell syntax.
set -euo pipefail

if [[ "${ALLOW_HEREDOC_CONTINUATION:-}" == "1" ]]; then
  exit 0
fi

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

python3 - "$cmd" <<'PY'
import json
import re
import sys

command = sys.argv[1]

delimiters = []
for match in re.finditer(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", command):
    delimiters.append(match.group(1))

if not delimiters:
    sys.exit(0)

for line in command.splitlines():
    stripped = line.strip()
    for delimiter in delimiters:
        if re.match(rf"^{re.escape(delimiter)}\s*(&&|\|\||;|\|)\s*\S", stripped):
            reason = (
                "Do not put shell syntax after a heredoc terminator line. "
                "Run the post-heredoc command in a separate shell call, or place "
                "the continuation before the heredoc begins."
            )
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }))
            sys.exit(0)

sys.exit(0)
PY
