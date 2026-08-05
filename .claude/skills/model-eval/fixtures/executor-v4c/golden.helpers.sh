#!/bin/sh
# agent-compat helpers: shared functions for the agent-compat CLI.

AGENT_COMPAT_VERSION="1.4.0"

# agent_compat_root — config root (env override, else default)
agent_compat_root() {
  printf '%s\n' "${AGENT_COMPAT_ROOT:-$HOME/.config/agent-compat}"
}

# agent_compat_normalize <name> — kebab-case an agent name
agent_compat_normalize() {
  printf '%s\n' "$1" | tr 'A-Z_' 'a-z-'
}

# agent_compat_strict — rc 0 when AGENT_COMPAT_STRICT=1
agent_compat_strict() {
  [ "${AGENT_COMPAT_STRICT:-0}" = "1" ]
}
