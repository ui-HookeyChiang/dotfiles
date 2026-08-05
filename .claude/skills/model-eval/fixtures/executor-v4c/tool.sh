#!/bin/sh
# agent-parity CLI: report agent definition parity across runtimes.
. "$(dirname "$0")/helpers.sh"

# parity_report — banner line with version and config root
parity_report() {
  root="$(agent_parity_root)"
  printf 'agent-parity v%s root=%s\n' "$AGENT_PARITY_VERSION" "$root"
}

# parity_check <name> — check one agent definition
parity_check() {
  name="$(agent_parity_normalize "$1")"
  if agent_parity_strict; then
    printf 'agent-parity: strict check %s\n' "$name"
  else
    printf 'agent-parity: check %s\n' "$name"
  fi
}
