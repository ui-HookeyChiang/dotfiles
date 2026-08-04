#!/usr/bin/env bash
# register-settings-hooks.sh — register all hooks from this repo into
# ~/.claude/settings.json. Default: CHECK-AND-NOTIFY (never writes).
# Pass --apply to merge entries.
#
# Safety: resolves symlinks, backs up before writing, validates JSON,
# atomic mv. Idempotent — re-running with entries present is a no-op.
#
# Usage: register-settings-hooks.sh [--apply] [--dry-run]
set -euo pipefail

APPLY=0
DRY_RUN=0
for a in "$@"; do
  case "$a" in
    --apply)   APPLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "  WARN: jq not found; cannot check settings hooks" >&2; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"
# shellcheck source=hooks/lib/registration-engine.sh
source "$SCRIPT_DIR/lib/registration-engine.sh"
# shellcheck source=scripts/lib/agent-detect.sh
source "$SCRIPT_DIR/../scripts/lib/agent-detect.sh"
registration_configure "$APPLY" "$DRY_RUN"

SETTINGS_LINK="$HOME/.claude/settings.json"
[ -e "$SETTINGS_LINK" ] || { echo "  WARN: $SETTINGS_LINK missing; skipping hook registration" >&2; exit 0; }

if command -v readlink >/dev/null 2>&1 && [ -L "$SETTINGS_LINK" ]; then
  SETTINGS="$(readlink -f "$SETTINGS_LINK" 2>/dev/null || echo "$SETTINGS_LINK")"
else
  SETTINGS="$SETTINGS_LINK"
fi

render_manifest_for() {
  local harness="$1" expand_home="${2:-0}" rendered
  rendered="$(registration_render_manifest_hooks "$MANIFEST" "$harness")"
  if [ "$expand_home" -eq 1 ]; then
    printf '%s' "$rendered" | registration_expand_home_json
  else
    printf '%s' "$rendered"
  fi
}

register_manifest_hooks_file() {
  local harness="$1" target="$2" label="$3" shape="$4" expand_home="$5"
  local rendered missing existing merged tmp success

  rendered="$(render_manifest_for "$harness" "$expand_home")"

  if [ "$APPLY" -eq 1 ]; then
    if [ -f "$target" ]; then
      if registration_emit_dry_run "  [would merge] $label"; then
        return 0
      fi
      existing="$(cat "$target")"
      success="  [merged] $label (backup: ${target}.bak)"
    else
      if registration_emit_dry_run "  [would install] $label (new)"; then
        return 0
      fi
      existing="{}"
      success="  [installed] $label (new)"
    fi

    mkdir -p "$(dirname "$target")"
    merged="$(registration_merge_hooks_json "$existing" "$rendered" "$shape")"
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    printf '%s' "$merged" | jq '.' > "$tmp"
    registration_write_json_file "$target" "$tmp" "$label" "$success"
    return
  fi

  if [ ! -f "$target" ]; then
    echo ""
    echo "  [missing] $label — hooks not installed."
    echo "  To install, re-run: ./install.sh --register-hooks"
    return
  fi

  missing="$(registration_count_missing_hooks "$target" "$rendered" "$shape")"
  if [ "$missing" -gt 0 ]; then
    echo ""
    echo "  [missing] $missing hook(s) not registered in $label"
    echo "  To install, re-run: ./install.sh --register-hooks"
  fi
}

register_manifest_hooks_file "claude" "$SETTINGS" "~/.claude/settings.json" "nested" 0

# ============================================================================
# Codex CLI hooks registration
# ============================================================================
# Installs manifest-rendered hooks into ~/.codex/hooks.json (merge-preserving).
# Only runs when --apply is passed AND codex is installed (or ~/.codex/ exists).

CODEX_DIR="$HOME/.codex"
CODEX_HOOKS="$CODEX_DIR/hooks.json"

if agent_installed codex; then
  register_manifest_hooks_file "codex" "$CODEX_HOOKS" "~/.codex/hooks.json" "nested" 1
fi

# ============================================================================
# Codex parity config and agent definitions
# ============================================================================
# Installs repo-managed deny manifest and multi-agent prompts used by parity
# checks. Codex enforces denials through hooks; this file records the mirrored
# policy surface for deterministic parity accounting.

CODEX_CONFIG="$CODEX_DIR/cli-config.json"
CODEX_CONFIG_TEMPLATE="$SCRIPT_DIR/codex/cli-config.json"
CODEX_AGENTS_DIR="$CODEX_DIR/agents"
CODEX_AGENTS_TEMPLATE_DIR="$SCRIPT_DIR/codex/agents"

if [ -f "$CODEX_CONFIG_TEMPLATE" ]; then
  if agent_installed codex; then
    if [ "$APPLY" -eq 1 ]; then
      if registration_emit_dry_run "  [would install] ~/.codex/cli-config.json"; then
        :
      else
        mkdir -p "$CODEX_DIR"
        TMP="$(mktemp "${CODEX_CONFIG}.tmp.XXXXXX")"
        jq '.' "$CODEX_CONFIG_TEMPLATE" > "$TMP"
        registration_write_json_file "$CODEX_CONFIG" "$TMP" "~/.codex/cli-config.json" "  [installed] ~/.codex/cli-config.json"
      fi
    elif [ ! -f "$CODEX_CONFIG" ]; then
      echo ""
      echo "  [missing] ~/.codex/cli-config.json — Codex deny parity manifest not installed."
      echo "  To install, re-run: ./install.sh --register-hooks"
    fi
  fi
fi

if [ -d "$CODEX_AGENTS_TEMPLATE_DIR" ]; then
  if agent_installed codex; then
    if [ "$APPLY" -eq 1 ]; then
      if registration_emit_dry_run "  [would install] ~/.codex/agents/{scan,execute,decide,exploration}.md"; then
        :
      else
        mkdir -p "$CODEX_AGENTS_DIR"
        for template in "$CODEX_AGENTS_TEMPLATE_DIR"/*.md; do
          [ -e "$template" ] || continue
          target="$CODEX_AGENTS_DIR/$(basename "$template")"
          if [ -f "$target" ] && cmp -s "$template" "$target"; then
            continue
          fi
          [ ! -f "$target" ] || cp "$target" "${target}.bak"
          cp "$template" "$target"
        done
        echo "  [installed] ~/.codex/agents/{scan,execute,decide,exploration}.md"
      fi
    else
      CODEX_AGENT_MISSING=0
      for template in "$CODEX_AGENTS_TEMPLATE_DIR"/*.md; do
        [ -e "$template" ] || continue
        target="$CODEX_AGENTS_DIR/$(basename "$template")"
        [ -f "$target" ] || CODEX_AGENT_MISSING=$((CODEX_AGENT_MISSING + 1))
      done
      if [ "$CODEX_AGENT_MISSING" -gt 0 ]; then
        echo ""
        echo "  [missing] $CODEX_AGENT_MISSING Codex agent definition(s) not installed in ~/.codex/agents"
        echo "  To install, re-run: ./install.sh --register-hooks"
      fi
    fi
  fi
fi

# ============================================================================
# Cursor hooks registration
# ============================================================================
# Installs manifest-rendered hooks into ~/.cursor/hooks.json (merge-preserving).
# Also symlinks translate-hook.sh into ~/.claude/hooks/cursor/ so commands
# in the template resolve. Only runs when --apply AND cursor is detected.

CURSOR_DIR="$HOME/.cursor"
CURSOR_HOOKS="$CURSOR_DIR/hooks.json"
CURSOR_TRANSLATE="$SCRIPT_DIR/cursor/translate-hook.sh"

_cursor_detected() {
  agent_installed cursor
}

if _cursor_detected; then
  if [ "$APPLY" -eq 1 ]; then
    registration_symlink "$CURSOR_TRANSLATE" "$HOME/.claude/hooks/cursor/translate-hook.sh" \
      "  [would symlink] ~/.claude/hooks/cursor/translate-hook.sh" \
      "  [symlinked] ~/.claude/hooks/cursor/translate-hook.sh"
  fi
  register_manifest_hooks_file "cursor" "$CURSOR_HOOKS" "~/.cursor/hooks.json" "flat" 1
fi

exit 0
