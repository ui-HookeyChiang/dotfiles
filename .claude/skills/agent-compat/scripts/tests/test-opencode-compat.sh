#!/usr/bin/env bash
# Verify OpenCode compatibility accounting across docs, hooks, and agent definitions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPAT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$COMPAT_ROOT/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p   "$FAKE_HOME/.claude/hooks"   "$FAKE_HOME/.claude/agents"   "$FAKE_HOME/.config/opencode/plugins"   "$FAKE_HOME/.config/opencode/agents"   "$FAKE_BIN"

printf '#!/usr/bin/env bash
exit 0
' > "$FAKE_BIN/claude"
printf '#!/usr/bin/env bash
exit 0
' > "$FAKE_BIN/opencode"
chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/opencode"

for doc in memory-discipline terse-output model-dispatch-claude sandbox-protected-paths; do
  ln -s "$REPO_ROOT/docs/agents/$doc.md" "$FAKE_HOME/.claude/$doc.md"
  ln -s "$REPO_ROOT/docs/agents/$doc.md" "$FAKE_HOME/.config/opencode/$doc.md"
done

printf '%s
'   '@memory-discipline.md'   '@terse-output.md'   '@sandbox-protected-paths.md'   '@model-dispatch-claude.md'   > "$FAKE_HOME/.claude/CLAUDE.md"

for agent in decide execute execute-deep execute-review scan scan-search; do
  ln -s "$REPO_ROOT/docs/agent-definitions/$agent.md" "$FAKE_HOME/.claude/agents/$agent.md"
done
printf 'Delivery Red Lines
' > "$FAKE_HOME/.config/opencode/agents/inject.md"
ln -s "$REPO_ROOT/hooks/opencode/skill-dev-hooks.ts" "$FAKE_HOME/.config/opencode/plugins/skill-dev-hooks.ts"
for plugin in block-main-edit check-compat-session guard-stale-base rtk; do
  printf '// fake plugin
' > "$FAKE_HOME/.config/opencode/plugins/$plugin.js"
done

printf '%s
' '{
  "model": "claude-opus-4-6",
  "permissions": {
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf /*)",
      "Bash(git push --force *)",
      "Bash(git push -f *)",
      "Bash(git reset --hard *)",
      "Bash(git add -A:*)",
      "Bash(git add --all:*)",
      "Bash(git add .:*)",
      "Bash(gh pr edit * --title *)",
      "Bash(gh pr edit --title *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {"hooks":[{"command":"bash ~/.claude/hooks/block-main-edit.sh"}]},
      {"hooks":[{"command":"$HOME/.local/bin/rtk hook claude"}]},
      {"hooks":[{"command":"bash ~/.claude/hooks/guard-stale-base.sh"}]},
      {"hooks":[{"command":"bash ~/.claude/hooks/guard-agent-worktree.sh"}]},
      {"hooks":[{"command":"bash ~/.claude/hooks/block-bare-read.sh"}]}
    ],
    "SessionStart": [{"hooks":[{"command":"bash ~/.claude/hooks/check-compat-session.sh"}]}],
    "SubagentStart": [{"hooks":[{"command":"bash ~/.claude/hooks/subagent-dispatch-inject.sh"}]}]
  }
}' > "$FAKE_HOME/.claude/settings.json"

printf '%s
' '{
  "model": "github-copilot/claude-opus-4.6",
  "permission": {"bash": {
    "rm -rf /": "deny",
    "rm -rf /*": "deny",
    "git push --force *": "deny",
    "git push -f *": "deny",
    "git reset --hard *": "deny",
    "git add -A": "deny",
    "git add --all": "deny",
    "git add .": "deny",
    "gh pr edit * --title *": "deny",
    "gh pr edit --title *": "deny"
  }},
  "instructions": [
    "~/.config/opencode/memory-discipline.md",
    "~/.config/opencode/terse-output.md",
    "~/.config/opencode/model-dispatch-claude.md",
    "~/.config/opencode/sandbox-protected-paths.md"
  ],
  "agent": {
    "general": {"mode":"subagent", "prompt":"{file:./agents/general.md}"},
    "explore": {"mode":"subagent", "prompt":"{file:./agents/explore.md}"},
    "decide": {"mode":"subagent", "prompt":"{file:./agents/decide.md}"},
    "execute": {"mode":"subagent", "prompt":"{file:./agents/execute.md}"},
    "execute-deep": {"mode":"subagent", "prompt":"{file:./agents/execute-deep.md}"},
    "execute-review": {"mode":"subagent", "prompt":"{file:./agents/execute-review.md}"},
    "scan": {"mode":"subagent", "prompt":"{file:./agents/scan.md}"},
    "scan-search": {"mode":"subagent", "prompt":"{file:./agents/scan-search.md}"}
  }
}' > "$FAKE_HOME/.config/opencode/opencode.json"

OUTPUT="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" "$COMPAT_ROOT/scripts/check-compat.sh" --agent opencode --axis agent-definitions)"
if echo "$OUTPUT" | rg -q 'GAP:|DRIFTED|DIVERGED'; then
  echo "FAIL: opencode parity still has unaccepted gaps or drift" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
for accepted in general explore; do
  if ! echo "$OUTPUT" | rg -q "ACCEPTED: +$accepted"; then
    echo "FAIL: missing accepted exception for $accepted" >&2
    echo "$OUTPUT" >&2
    exit 1
  fi
done

if ! echo "$OUTPUT" | rg -q 'summary: 0 gap\(s\), 0 warning\(s\), 2 accepted exception\(s\)'; then
  echo "FAIL: unexpected opencode parity summary" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

echo "PASS: opencode parity reports no unaccepted gaps or drift"
