#!/bin/sh
# agent-parity helpers: shared functions for the agent-parity CLI.

AGENT_PARITY_VERSION="1.4.0"

# agent_parity_root — config root (env override, else default)
agent_parity_root() {
  printf '%s\n' "${AGENT_PARITY_ROOT:-$HOME/.config/agent-parity}"
}

# agent_parity_normalize <name> — kebab-case an agent name
agent_parity_normalize() {
  printf '%s\n' "$1" | tr 'A-Z_' 'a-z-'
}

# agent_parity_strict — rc 0 when AGENT_PARITY_STRICT=1
agent_parity_strict() {
  [ "${AGENT_PARITY_STRICT:-0}" = "1" ]
}
