#!/usr/bin/env bash
# detect-agents.sh — detect installed AI coding agents from descriptors.
# Output: JSON object with agent name, installed status, config paths.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DESCRIPTORS="${AGENT_COMPAT_DESCRIPTORS:-$SCRIPT_DIR/../descriptors/agents.json}"

resolve_path() {
  local path="$1"
  case "$path" in
    "") echo "" ;;
    \~/*) echo "$HOME/${path#\~/}" ;;
    /*) echo "$path" ;;
    *) echo "$REPO_ROOT/$path" ;;
  esac
}

probe_installed() {
  local encoded="$1" count type value expanded i
  count=$(echo "$encoded" | base64 -d | jq '.detection.probes | length')
  for ((i=0; i<count; i++)); do
    type=$(echo "$encoded" | base64 -d | jq -r ".detection.probes[$i].type")
    value=$(echo "$encoded" | base64 -d | jq -r ".detection.probes[$i].value")
    expanded=$(resolve_path "$value")
    case "$type" in
      command) command -v "$value" >/dev/null 2>&1 && return 0 ;;
      file)    [ -f "$expanded" ] && return 0 ;;
      dir)     [ -d "$expanded" ] && return 0 ;;
    esac
  done
  return 1
}

path_if_present() {
  local path="$1" kind="$2" expanded
  expanded=$(resolve_path "$path")
  [ -n "$expanded" ] || { echo ""; return; }
  case "$kind" in
    file) [ -f "$expanded" ] && echo "$expanded" || echo "" ;;
    dir)  [ -d "$expanded" ] && echo "$expanded" || echo "" ;;
    *)    echo "ERROR: path_if_present requires kind=file|dir, got '$kind'" >&2; echo "" ;;
  esac
}

agents='[]'
while IFS= read -r encoded; do
  [ -n "$encoded" ] || continue
  name=$(echo "$encoded" | base64 -d | jq -r '.name')
  installed=false
  probe_installed "$encoded" && installed=true

  if [ "$installed" = true ]; then
    settings=$(path_if_present "$(echo "$encoded" | base64 -d | jq -r '.paths.settings // ""')" file)
    instructions=$(path_if_present "$(echo "$encoded" | base64 -d | jq -r '.paths.instructions // ""')" file)
    permissions=$(path_if_present "$(echo "$encoded" | base64 -d | jq -r '.paths.permissions // ""')" file)
    agent_definitions=$(path_if_present "$(echo "$encoded" | base64 -d | jq -r '.paths.agent_definitions // ""')" dir)
    skills=$(path_if_present "$(echo "$encoded" | base64 -d | jq -r '.paths.skills // ""')" dir)
    hooks_path=$(echo "$encoded" | base64 -d | jq -r '.paths.hooks // ""')
    case "$hooks_path" in
      *json) hooks=$(path_if_present "$hooks_path" file) ;;
      *)    hooks=$(path_if_present "$hooks_path" dir) ;;
    esac
    agent=$(jq -n \
      --arg name "$name" \
      --arg settings "$settings" \
      --arg instructions "$instructions" \
      --arg hooks "$hooks" \
      --arg permissions "$permissions" \
      --arg agent_definitions "$agent_definitions" \
      --arg skills "$skills" \
      '{name:$name,installed:true,settings:$settings,instructions:$instructions,hooks:$hooks,permissions:$permissions,agent_definitions:$agent_definitions,skills:$skills}')
  else
    agent=$(jq -n --arg name "$name" '{name:$name,installed:false}')
  fi
  agents=$(jq --argjson agent "$agent" '. + [$agent]' <<< "$agents")
done < <(jq -r '.agents[] | @base64' "$DESCRIPTORS")

jq -n --argjson agents "$agents" '{agents:$agents}'
