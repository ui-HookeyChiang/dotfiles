#!/usr/bin/env bash
# detect-agents.sh — detect installed AI coding agents and their config paths.
# Output: JSON object with agent name, installed status, config paths.
set -euo pipefail

agents='{"agents":['
sep=""

# Claude Code
if command -v claude >/dev/null 2>&1; then
  settings="$HOME/.claude/settings.json"
  claudemd="$HOME/.claude/CLAUDE.md"
  hooks_dir="$HOME/.claude/hooks"
  [ -f "$settings" ] || settings=""
  [ -f "$claudemd" ] || claudemd=""
  [ -d "$hooks_dir" ] || hooks_dir=""
  agents+="${sep}{\"name\":\"claude\",\"installed\":true,\"settings\":\"$settings\",\"instructions\":\"$claudemd\",\"hooks\":\"$hooks_dir\"}"
  sep=","
else
  agents+="${sep}{\"name\":\"claude\",\"installed\":false}"
  sep=","
fi

# OpenCode
if command -v opencode >/dev/null 2>&1; then
  config="$HOME/.config/opencode/opencode.json"
  agentsmd="$HOME/.config/opencode/AGENTS.md"
  plugins_dir="$HOME/.config/opencode/plugins"
  [ -f "$config" ] || config=""
  [ -f "$agentsmd" ] || agentsmd=""
  [ -d "$plugins_dir" ] || plugins_dir=""
  agents+="${sep}{\"name\":\"opencode\",\"installed\":true,\"settings\":\"$config\",\"instructions\":\"$agentsmd\",\"hooks\":\"$plugins_dir\"}"
  sep=","
else
  agents+="${sep}{\"name\":\"opencode\",\"installed\":false}"
  sep=","
fi

agents+=']}'
echo "$agents" | jq '.'
