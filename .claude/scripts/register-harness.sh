#!/usr/bin/env bash
# register-harness.sh — descriptor-driven agent harness registration entry.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/register-harness.sh <claude|codex|cursor|opencode|--all> [--dry-run] [--configure-hooks]

Registers agent harness integration steps. Link-style work stays absent-only;
shared config mutation is opt-in via --configure-hooks.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/agent-detect.sh
source "$SCRIPT_DIR/lib/agent-detect.sh"

TARGET=""
DRY_RUN=0
CONFIGURE_HOOKS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --all|claude|codex|cursor|opencode) TARGET="$1"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --configure-hooks|--register-hooks) CONFIGURE_HOOKS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$TARGET" ] || { usage >&2; exit 2; }

if [ "$TARGET" = "--all" ]; then
  TARGETS=(claude codex cursor opencode)
else
  TARGETS=("$TARGET")
fi

HOOK_ARGS=()
[ "$CONFIGURE_HOOKS" -eq 1 ] && HOOK_ARGS+=(--apply)
[ "$DRY_RUN" -eq 1 ] && HOOK_ARGS+=(--dry-run)
NEEDS_HOOK_CHECK=0

for harness in "${TARGETS[@]}"; do
  if ! agent_installed "$harness"; then
    echo "Skipping $harness agent harness ($harness not detected)"
    continue
  fi

  case "$harness" in
    claude|codex|cursor)
      NEEDS_HOOK_CHECK=1
      echo "Detected $harness agent harness"
      ;;
    opencode)
      echo "Detected opencode agent harness"
      ;;
  esac
done

if [ "$NEEDS_HOOK_CHECK" -eq 1 ]; then
  bash "$REPO_ROOT/hooks/register-settings-hooks.sh" ${HOOK_ARGS[@]+"${HOOK_ARGS[@]}"}
fi
