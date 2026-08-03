#!/usr/bin/env bash
# Verify new registration adapters must route writes through the dry-run helper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=hooks/lib/registration-engine.sh
source "$REPO_ROOT/hooks/lib/registration-engine.sh"

if declare -F registration_should_write >/dev/null; then
  echo "FAIL: registration_should_write should be retired" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
TARGET="$TMP_ROOT/settings.json"
printf '{}
' > "$TARGET"

snapshot_files() {
  local root="$1"
  find "$root" -type f -print0 | sort -z | xargs -0 sha256sum
}

fake_adapter_register() {
  if registration_emit_dry_run "  [would fake-register] settings.json"; then
    return 0
  fi

  local tmp
  tmp="$(mktemp "${TARGET}.tmp.XXXXXX")"
  jq '.hooks = {fake: true}' "$TARGET" > "$tmp"
  registration_write_json_file "$TARGET" "$tmp" "fake-adapter" "  [fake-registered] settings.json"
}

registration_configure 1 1
before="$(snapshot_files "$TMP_ROOT")"
fake_adapter_register >/dev/null
after="$(snapshot_files "$TMP_ROOT")"
if [ "$before" != "$after" ]; then
  echo "FAIL: fake adapter mutated files during dry-run" >&2
  diff <(echo "$before") <(echo "$after") >&2
  exit 1
fi

registration_configure 1 0
fake_adapter_register >/dev/null
if ! jq -e '.hooks.fake == true' "$TARGET" >/dev/null; then
  echo "FAIL: fake adapter did not write through shared registration helper" >&2
  exit 1
fi

if [ ! -f "${TARGET}.bak" ]; then
  echo "FAIL: shared registration helper did not create backup" >&2
  exit 1
fi

rendered="$(registration_render_manifest_hooks "$REPO_ROOT/hooks/manifest.json" claude)"
merged="$(registration_merge_hooks_json '{}' "$rendered" nested)"
if ! echo "$merged" | jq -e '.hooks.PreToolUse | length == 6' >/dev/null; then
  echo "FAIL: manifest render/merge did not produce Claude PreToolUse hooks" >&2
  echo "$merged" >&2
  exit 1
fi

codex_rendered="$(registration_render_manifest_hooks "$REPO_ROOT/hooks/manifest.json" codex)"
if ! echo "$codex_rendered" | jq -e '
  [.hooks.PreToolUse[]?.hooks[]?.command]
  | any(. == "$HOME/.local/bin/rtk hook claude")
' >/dev/null; then
  echo "FAIL: rtk hook command must not depend on PATH lookup" >&2
  echo "$codex_rendered" >&2
  exit 1
fi

echo "PASS: registration engine enforces dry-run for new adapters"
