#!/usr/bin/env bash
# Verify install.sh registers OpenCode parity surfaces and removes legacy shell-search denies.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.config/opencode" "$FAKE_BIN"
printf '{}\n' > "$FAKE_HOME/.claude/settings.json"
printf '#!/usr/bin/env bash
exit 0
' > "$FAKE_BIN/opencode"
chmod +x "$FAKE_BIN/opencode"

printf '%s
' '{
  "model": "github-copilot/claude-opus-4.6",
  "permission": {"bash": {
    "grep *": "deny",
    "egrep *": "deny",
    "fgrep *": "deny",
    "find *": "deny"
  }},
  "instructions": ["~/.config/opencode/memory-discipline.md"],
  "agent": {"general": {"mode":"subagent", "prompt":"{file:./agents/general.md}"}}
}' > "$FAKE_HOME/.config/opencode/opencode.json"

HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" CLAUDE_SKILLS_DIR="$FAKE_HOME/.claude/skills" \
  SKILL_INSTALL_ALLOW_WORKTREE=1 \
  bash "$REPO_ROOT/install.sh" --skip-bins --skip-extras --force >/dev/null

for doc in memory-discipline terse-output model-dispatch-claude sandbox-protected-paths; do
  [ -L "$FAKE_HOME/.config/opencode/$doc.md" ] || { echo "FAIL: missing opencode doc symlink $doc" >&2; exit 1; }
  jq -e --arg doc "~/.config/opencode/$doc.md" '.instructions | index($doc)' "$FAKE_HOME/.config/opencode/opencode.json" >/dev/null
done

for agent in decide execute execute-deep execute-review scan scan-search; do
  [ -L "$FAKE_HOME/.claude/agents/$agent.md" ] || { echo "FAIL: missing claude agent symlink $agent" >&2; exit 1; }
  [ -f "$FAKE_HOME/.config/opencode/agents/$agent.md" ] || { echo "FAIL: missing opencode agent file $agent" >&2; exit 1; }
  [ ! -L "$FAKE_HOME/.config/opencode/agents/$agent.md" ] || { echo "FAIL: opencode agent should be generated file, not symlink: $agent" >&2; exit 1; }
  jq -e --arg agent "$agent" '.agent[$agent].prompt == ("{file:./agents/" + $agent + ".md}")' "$FAKE_HOME/.config/opencode/opencode.json" >/dev/null
done

grep -q '^color: cyan$' "$FAKE_HOME/.claude/agents/scan.md"
grep -q '^color: cyan$' "$FAKE_HOME/.claude/agents/scan-search.md"
grep -q '^color: green$' "$FAKE_HOME/.claude/agents/execute.md"
grep -q '^color: green$' "$FAKE_HOME/.claude/agents/execute-deep.md"
grep -q '^color: green$' "$FAKE_HOME/.claude/agents/execute-review.md"
grep -q '^color: yellow$' "$FAKE_HOME/.claude/agents/decide.md"
grep -q '^color: info$' "$FAKE_HOME/.config/opencode/agents/scan.md"
grep -q '^color: info$' "$FAKE_HOME/.config/opencode/agents/scan-search.md"
grep -q '^color: success$' "$FAKE_HOME/.config/opencode/agents/execute.md"
grep -q '^color: success$' "$FAKE_HOME/.config/opencode/agents/execute-deep.md"
grep -q '^color: success$' "$FAKE_HOME/.config/opencode/agents/execute-review.md"
grep -q '^color: warning$' "$FAKE_HOME/.config/opencode/agents/decide.md"

for deny in 'grep *' 'egrep *' 'fgrep *' 'find *'; do
  if jq -e --arg deny "$deny" '.permission.bash | has($deny)' "$FAKE_HOME/.config/opencode/opencode.json" >/dev/null; then
    echo "FAIL: legacy opencode search deny still present: $deny" >&2
    exit 1
  fi
done
jq -e '.plugin | index("./plugins/skill-dev-hooks.ts")' "$FAKE_HOME/.config/opencode/opencode.json" >/dev/null

printf 'PASS: install.sh syncs OpenCode parity surface and removes legacy search denies
'
