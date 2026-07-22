#!/usr/bin/env bash
# skill-audit — semantic leg CLI entry (thin wrapper over semantic_audit.py).
# Surface mirrors the SKILL.md argument-hint:
#   <path-to-SKILL.md> [--cross <dir>] [--axis G1|G8]
# Exit codes (advisory-mode, per SKILL.md "Exit code contract"):
#   0 = flagged (>=1 finding) | 2 = clean | 1 = tool/LLM failure
# --help always exits 0.
# Note: G7 paragraph density was removed 2026-05-29; --axis G7 returns
# exit 1 with a redirect message pointing at `prose-guidelines`.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_ENTRY="${SCRIPT_DIR}/semantic_audit.py"

usage() {
  cat <<'USAGE'
Usage: semantic_audit.sh <path-to-SKILL.md> [--cross <dir>] [--axis G1|G8]

Positional:
  <path-to-SKILL.md>   target SKILL.md to audit

Options:
  --cross <dir>        directory of skills for G1 cross-skill comparison
  --axis G1|G8         restrict to a single axis (default: both)
  --help               show this help and exit 0

Exit codes: 0=flagged | 2=clean | 1=tool/LLM failure
(See skill-audit/SKILL.md for the full contract.)
USAGE
}

# --help short-circuit before delegating to Python.
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "audit.sh: python3 not found on PATH" >&2
  exit 1
fi

exec python3 "${PY_ENTRY}" "$@"
