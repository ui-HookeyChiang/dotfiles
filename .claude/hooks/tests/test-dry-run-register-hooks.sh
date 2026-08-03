#!/usr/bin/env bash
# test-dry-run-register-hooks.sh — verify --dry-run --apply creates no files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../register-settings-hooks.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

snapshot_files() {
  local root="$1"
  find "$root" -type f -print0 | sort -z | xargs -0 sha256sum
}

snapshot_symlinks() {
  local root="$1"
  find "$root" -type l -print | sort
}

run_case() {
  local name="$1" seed_existing_hooks="$2"
  local fake_home="$TMP_ROOT/$name"

  mkdir -p "$fake_home/.claude" "$fake_home/.codex" "$fake_home/.cursor"
  echo '{}' > "$fake_home/.claude/settings.json"

  if [ "$seed_existing_hooks" -eq 1 ]; then
    echo '{"hooks":{"PreToolUse":[]}}' > "$fake_home/.codex/hooks.json"
    echo '{"version":1,"hooks":{"preToolUse":[]}}' > "$fake_home/.cursor/hooks.json"
  fi

  local before_files before_symlinks after_files after_symlinks
  before_files="$(snapshot_files "$fake_home")"
  before_symlinks="$(snapshot_symlinks "$fake_home")"

  HOME="$fake_home" bash "$HOOK_SCRIPT" --apply --dry-run

  after_files="$(snapshot_files "$fake_home")"
  after_symlinks="$(snapshot_symlinks "$fake_home")"

  if [ "$before_files" != "$after_files" ]; then
    echo "FAIL: $name mutated files in \$HOME" >&2
    diff <(echo "$before_files") <(echo "$after_files") >&2
    exit 1
  fi

  if [ "$before_symlinks" != "$after_symlinks" ]; then
    echo "FAIL: $name mutated symlinks in \$HOME" >&2
    diff <(echo "$before_symlinks") <(echo "$after_symlinks") >&2
    exit 1
  fi
}

run_case new-file 0
run_case merge 1

echo "PASS: --dry-run --apply produced zero file mutations for new-file and merge cases"
