#!/bin/bash
# skill-audit/scripts/syntax_audit.sh — entry point (syntax leg).
#
# Single-skill advisory (default — metrics + LLM):
#   bash syntax_audit.sh <path-to-SKILL.md>                          # advisory + LLM
#   bash syntax_audit.sh <path-to-SKILL.md> --no-llm                 # advisory, metrics only
#   bash syntax_audit.sh <path-to-SKILL.md> --metrics                # synonym of --no-llm
#   bash syntax_audit.sh <path-to-SKILL.md> --with-llm               # explicit (= default)
#   bash syntax_audit.sh <path-to-SKILL.md> --no-llm --json
# Single-skill legacy detectors (opt-in via spec flags):
#   bash syntax_audit.sh <path-to-SKILL.md> --write-spec
#   bash syntax_audit.sh <path-to-SKILL.md> --no-spec
# Advisory rank-all:
#   bash syntax_audit.sh --rank-all <dir> [--with-llm] [--top N] [--llm-timeout SECS]
#
# Exit codes:
#   0 — report ok (advisory composite ≥ threshold) or findings emitted (legacy)
#   1 — error (incl. real LLM dispatch failure when LLM was explicitly requested)
#   2 — no findings (legacy) or composite < threshold (advisory)
#
# Note: when invoked from the CLI without an Agent-tool harness, advisory mode
# falls back to metrics-only output with a stderr warning ("LLM unavailable,
# falling back to metrics") rather than exiting 1. Exit code still follows
# composite-vs-threshold.
set -uo pipefail

if [[ $# -lt 1 ]]; then
  cat >&2 <<USAGE
Usage:
  bash syntax_audit.sh <path-to-SKILL.md> [--no-llm | --metrics | --with-llm | --json | --llm-timeout SECS]
  bash syntax_audit.sh <path-to-SKILL.md> --write-spec | --no-spec       (legacy detectors)
  bash syntax_audit.sh --rank-all <dir> [--with-llm] [--top N] [--llm-timeout SECS]
USAGE
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/syntax_audit.py" "$@"
