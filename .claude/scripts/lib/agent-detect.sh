#!/usr/bin/env bash
# Shared descriptor-driven agent harness detection.

AGENT_DETECT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DETECT_REPO_ROOT="$(cd "$AGENT_DETECT_LIB_DIR/../.." && pwd)"

agent_installed() {
  local name="$1"
  AGENT_COMPAT_DESCRIPTORS="${AGENT_COMPAT_DESCRIPTORS:-$AGENT_DETECT_REPO_ROOT/agent-compat/descriptors/agents.json}" \
    "$AGENT_DETECT_REPO_ROOT/agent-compat/scripts/detect-agents.sh" \
    | jq -e --arg name "$name" '.agents[] | select(.name == $name and .installed == true)' >/dev/null
}
