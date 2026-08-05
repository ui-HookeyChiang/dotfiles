#!/bin/sh
# agent-compat CLI: report agent definition compatibility across runtimes.
. "$(dirname "$0")/helpers.sh"

# compat_report — banner line with version and config root
compat_report() {
  root="$(agent_compat_root)"
  printf 'agent-compat v%s root=%s\n' "$AGENT_COMPAT_VERSION" "$root"
}

# compat_check <name> — check one agent definition
compat_check() {
  name="$(agent_compat_normalize "$1")"
  if agent_compat_strict; then
    printf 'agent-compat: strict check %s\n' "$name"
  else
    printf 'agent-compat: check %s\n' "$name"
  fi
}
