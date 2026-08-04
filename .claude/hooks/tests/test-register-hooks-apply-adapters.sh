#!/usr/bin/env bash
# Verify --apply routes Codex/Cursor adapter writes through shared JSON writer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../register-settings-hooks.sh"
HOOK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_HOME="$TMP_ROOT/home"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.codex" "$FAKE_HOME/.cursor"
printf '{}
' > "$FAKE_HOME/.claude/settings.json"
printf '{"hooks":{"PreToolUse":[]}}
' > "$FAKE_HOME/.codex/hooks.json"
printf '{"permissions":{"deny":[]}}
' > "$FAKE_HOME/.codex/cli-config.json"
printf '{"version":1,"hooks":{"preToolUse":[]}}
' > "$FAKE_HOME/.cursor/hooks.json"

HOME="$FAKE_HOME" bash "$HOOK_SCRIPT" --apply >/dev/null

jq -e '.hooks.PreToolUse | length > 0' "$FAKE_HOME/.claude/settings.json" >/dev/null
jq -e '.hooks.PreToolUse | length > 0' "$FAKE_HOME/.codex/hooks.json" >/dev/null
jq -e '.hooks.preToolUse | length > 0' "$FAKE_HOME/.cursor/hooks.json" >/dev/null

# Load registration engine before using expected hook sets
source "$HOOK_ROOT/lib/registration-engine.sh"

# Assert hook sets match manifest (prevents compensating adds masking removals)
EXPECTED_CLAUDE="$(registration_render_manifest_hooks "$HOOK_ROOT/manifest.json" claude | HOME="$FAKE_HOME" registration_expand_home_json)"
EXPECTED_CODEX="$(registration_render_manifest_hooks "$HOOK_ROOT/manifest.json" codex | HOME="$FAKE_HOME" registration_expand_home_json)"

# Claude PreToolUse: exact set by command names
if ! jq -e --argjson expected "$(echo "$EXPECTED_CLAUDE" | jq -c '.hooks.PreToolUse | map(.hooks[0].command) | sort')" '
  [.hooks.PreToolUse[]?.hooks[]?.command] | sort | . == $expected
' "$FAKE_HOME/.claude/settings.json" >/dev/null; then
  echo "FAIL: Claude PreToolUse commands do not match expected set" >&2
  exit 1
fi

# Codex PreToolUse: exact set by command names
if ! jq -e --argjson expected "$(echo "$EXPECTED_CODEX" | jq -c '.hooks.PreToolUse | map(.hooks[0].command) | sort')" '
  [.hooks.PreToolUse[]?.hooks[]?.command] | sort | . == $expected
' "$FAKE_HOME/.codex/hooks.json" >/dev/null; then
  echo "FAIL: Codex PreToolUse commands do not match expected set" >&2
  exit 1
fi

# Claude SubagentStart: assert count
jq -e '(.hooks.SubagentStart | length) == 1' "$FAKE_HOME/.claude/settings.json" >/dev/null
# Codex SubagentStart: assert count
jq -e '(.hooks.SubagentStart | length) == 1' "$FAKE_HOME/.codex/hooks.json" >/dev/null

# Cursor hooks: assert present and count permissions
jq -e '.hooks.preToolUse | length > 0' "$FAKE_HOME/.cursor/hooks.json" >/dev/null
jq -e '.permissions.deny | length == 10' "$FAKE_HOME/.codex/cli-config.json" >/dev/null
[ -f "$FAKE_HOME/.codex/agents/scan.md" ]
[ -f "$FAKE_HOME/.codex/agents/execute.md" ]
[ -f "$FAKE_HOME/.codex/agents/decide.md" ]
[ -f "$FAKE_HOME/.codex/agents/exploration.md" ]

if ! jq -e --arg home "$FAKE_HOME" '[.. | strings] | any(contains($home))' "$FAKE_HOME/.codex/hooks.json" >/dev/null; then
  echo "FAIL: Codex template did not expand literal HOME" >&2
  exit 1
fi
if ! jq -e --arg home "$FAKE_HOME" '[.. | strings] | any(contains($home))' "$FAKE_HOME/.cursor/hooks.json" >/dev/null; then
  echo "FAIL: Cursor template did not expand literal HOME" >&2
  exit 1
fi
if ! jq -e --arg cmd "$FAKE_HOME/.local/bin/rtk hook claude" '
  [.hooks.PreToolUse[]?.hooks[]?.command] | any(. == $cmd)
' "$FAKE_HOME/.codex/hooks.json" >/dev/null; then
  echo "FAIL: Codex rtk hook command depends on PATH lookup" >&2
  exit 1
fi

if jq -e '.hooks[] | select(.name == "block-bare-read") | .harnesses.codex' "$HOOK_ROOT/manifest.json" >/dev/null 2>&1; then
  echo "FAIL: block-bare-read hook should not have codex harness" >&2
  exit 1
fi

EXPECTED_CURSOR="$(registration_render_manifest_hooks "$HOOK_ROOT/manifest.json" cursor | HOME="$FAKE_HOME" registration_expand_home_json)"
if ! diff <(echo "$EXPECTED_CODEX" | jq -S '.') <(jq -S '{hooks}' "$FAKE_HOME/.codex/hooks.json") >/dev/null; then
  echo "FAIL: Codex hooks output does not match manifest render" >&2
  diff <(echo "$EXPECTED_CODEX" | jq -S '.') <(jq -S '{hooks}' "$FAKE_HOME/.codex/hooks.json") >&2
  exit 1
fi
if ! diff <(echo "$EXPECTED_CURSOR" | jq -S '.') <(jq -S '{version, hooks}' "$FAKE_HOME/.cursor/hooks.json") >/dev/null; then
  echo "FAIL: Cursor hooks output does not match manifest render" >&2
  diff <(echo "$EXPECTED_CURSOR" | jq -S '.') <(jq -S '{version, hooks}' "$FAKE_HOME/.cursor/hooks.json") >&2
  exit 1
fi

[ -f "$FAKE_HOME/.claude/settings.json.bak" ]
[ -f "$FAKE_HOME/.codex/hooks.json.bak" ]
[ -f "$FAKE_HOME/.codex/cli-config.json.bak" ]
[ -f "$FAKE_HOME/.cursor/hooks.json.bak" ]

echo "PASS: --apply adapter writes validate, expand templates, and create backups"
