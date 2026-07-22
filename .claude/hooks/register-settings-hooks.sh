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

SETTINGS_LINK="$HOME/.claude/settings.json"
[ -e "$SETTINGS_LINK" ] || { echo "  WARN: $SETTINGS_LINK missing; skipping hook registration" >&2; exit 0; }

if command -v readlink >/dev/null 2>&1 && [ -L "$SETTINGS_LINK" ]; then
  SETTINGS="$(readlink -f "$SETTINGS_LINK" 2>/dev/null || echo "$SETTINGS_LINK")"
else
  SETTINGS="$SETTINGS_LINK"
fi

# Hook registry as parallel arrays (avoids delimiter conflicts with matcher pipes)
HOOK_EVENTS=(     "PreToolUse"    "PreToolUse"  "PreToolUse"  "PreToolUse"  "SubagentStart")
HOOK_MATCHERS=(   "Edit|Write|MultiEdit|NotebookEdit" "Bash" \
                  "Edit|Write|MultiEdit|NotebookEdit" "Bash" "")
HOOK_CMDS=(       "bash ~/.claude/hooks/block-main-edit.sh" \
                  "bash ~/.claude/hooks/guard-stale-base.sh" \
                  "bash ~/.claude/hooks/guard-agent-worktree.sh" \
                  "bash ~/.claude/hooks/guard-agent-worktree.sh" \
                  "bash ~/.claude/hooks/subagent-dispatch-inject.sh")
HOOK_TIMEOUTS=(   10 15 10 10 10)
HOOK_STATUS_MSGS=("Enforcing worktree-only edits" \
                  "Checking base branch freshness" \
                  "Enforcing agent worktree isolation" \
                  "Enforcing agent worktree isolation" \
                  "")
HOOK_DESCS=(      "Block edits in main working tree (forces worktree isolation)" \
                  "Block branching from bare local refs, auto-fetch remote refs" \
                  "Block subagent file edits outside assigned worktree" \
                  "Block subagent write-type git ops outside assigned worktree" \
                  "Inject delivery red lines and failure escalation into subagents")

MISSING=0
PRESENT=0
REGISTERED=0
HOOK_COUNT=${#HOOK_EVENTS[@]}

for ((i=0; i<HOOK_COUNT; i++)); do
  event="${HOOK_EVENTS[$i]}"
  matcher="${HOOK_MATCHERS[$i]}"
  cmd="${HOOK_CMDS[$i]}"
  timeout="${HOOK_TIMEOUTS[$i]}"
  status_msg="${HOOK_STATUS_MSGS[$i]}"
  description="${HOOK_DESCS[$i]}"

  # Check if already registered
  if jq -e --arg c "$cmd" \
        "[.hooks.${event}[]?.hooks[]?.command] | any(. == \$c)" \
        "$SETTINGS" >/dev/null 2>&1; then
    PRESENT=$((PRESENT + 1))
    continue
  fi

  MISSING=$((MISSING + 1))

  if [ "$APPLY" -eq 0 ]; then
    printf "  [missing] %-12s %-50s\n" "$event:" "$description"
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf "  [would register] %-12s %s\n" "$event:" "$cmd"
    continue
  fi

  # Build hook object
  hook_obj="{\"type\":\"command\",\"command\":$(jq -n --arg c "$cmd" '$c'),\"timeout\":$timeout"
  [ -n "$status_msg" ] && hook_obj+=",\"statusMessage\":$(jq -n --arg s "$status_msg" '$s')"
  hook_obj+="}"

  # Build entry object (with or without matcher)
  if [ -n "$matcher" ]; then
    entry_obj="{\"matcher\":$(jq -n --arg m "$matcher" '$m'),\"hooks\":[$hook_obj]}"
  else
    entry_obj="{\"hooks\":[$hook_obj]}"
  fi

  TMP="$(mktemp "${SETTINGS}.tmp.XXXXXX")"

  if ! jq --argjson entry "$entry_obj" \
        ".hooks //= {}
         | .hooks.${event} //= []
         | .hooks.${event} += [\$entry]" \
        "$SETTINGS" > "$TMP"; then
    echo "  WARN: jq merge failed for $cmd; skipping" >&2
    rm -f "$TMP"
    continue
  fi

  if ! jq empty "$TMP" >/dev/null 2>&1 || [ ! -s "$TMP" ]; then
    echo "  WARN: validation failed for $cmd; skipping" >&2
    rm -f "$TMP"
    continue
  fi

  cp "$SETTINGS" "${SETTINGS}.bak"
  mv "$TMP" "$SETTINGS"
  printf "  [registered] %-12s %s\n" "$event:" "$description"
  REGISTERED=$((REGISTERED + 1))
done

# Summary
if [ "$APPLY" -eq 0 ] && [ "$MISSING" -gt 0 ]; then
  echo ""
  echo "  $MISSING hook(s) not registered. To enable, re-run:"
  echo "      ./install.sh --register-hooks"
  echo "  This merges hooks into ~/.claude/settings.json (backed up first)."
  echo "  Restart Claude Code to activate."
fi

if [ "$REGISTERED" -gt 0 ]; then
  echo ""
  echo "  $REGISTERED hook(s) registered. Backup: ${SETTINGS}.bak"
  echo "  Restart Claude Code to activate."
fi

# ============================================================================
# Codex CLI hooks registration
# ============================================================================
# Installs hooks/codex/hooks.json as ~/.codex/hooks.json (merge-preserving).
# Only runs when --apply is passed AND codex is installed (or ~/.codex/ exists).

CODEX_DIR="$HOME/.codex"
CODEX_HOOKS="$CODEX_DIR/hooks.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_TEMPLATE="$SCRIPT_DIR/codex/hooks.json"

if [ "$APPLY" -eq 1 ] && [ -f "$CODEX_TEMPLATE" ]; then
  # Gate: only if codex is installed or ~/.codex/ already exists
  if command -v codex >/dev/null 2>&1 || [ -d "$CODEX_DIR" ]; then
    mkdir -p "$CODEX_DIR"

    if [ ! -f "$CODEX_HOOKS" ]; then
      # Expand $HOME in template and install fresh
      sed "s|\\\$HOME|$HOME|g" "$CODEX_TEMPLATE" > "$CODEX_HOOKS"
      echo "  [installed] ~/.codex/hooks.json (new)"
    else
      # Merge: add our hook entries that aren't already present (by command string)
      cp "$CODEX_HOOKS" "${CODEX_HOOKS}.bak"

      EXPANDED_TEMPLATE="$(sed "s|\\\$HOME|$HOME|g" "$CODEX_TEMPLATE")"
      MERGED="$(jq -n \
        --argjson existing "$(cat "$CODEX_HOOKS")" \
        --argjson template "$EXPANDED_TEMPLATE" '
        $existing
        | .hooks //= {}
        | reduce ($template.hooks | to_entries[]) as {$key, $value} (.;
            .hooks[$key] //= []
            | reduce $value[] as $entry (.;
                if ([.hooks[$key][]?.hooks[]?.command] | any(. == ($entry.hooks[0].command)))
                then .
                else .hooks[$key] += [$entry]
                end
            )
        )
      ')"

      if printf '%s' "$MERGED" | jq empty >/dev/null 2>&1; then
        printf '%s' "$MERGED" | jq '.' > "$CODEX_HOOKS"
        echo "  [merged] ~/.codex/hooks.json (backup: ${CODEX_HOOKS}.bak)"
      else
        echo "  WARN: Codex hooks merge produced invalid JSON; skipping" >&2
      fi
    fi
  fi
elif [ "$APPLY" -eq 0 ] && [ -f "$CODEX_TEMPLATE" ]; then
  if command -v codex >/dev/null 2>&1 || [ -d "$CODEX_DIR" ]; then
    if [ ! -f "$CODEX_HOOKS" ]; then
      echo ""
      echo "  [missing] ~/.codex/hooks.json — Codex hooks not installed."
      echo "  To install, re-run: ./install.sh --register-hooks"
    else
      # Check if our hooks are already present
      EXPANDED_TEMPLATE="$(sed "s|\\\$HOME|$HOME|g" "$CODEX_TEMPLATE")"
      CODEX_MISSING=0
      while IFS= read -r cmd; do
        if ! jq -e --arg c "$cmd" \
              '[.hooks[]?[]?.hooks[]?.command] | any(. == $c)' \
              "$CODEX_HOOKS" >/dev/null 2>&1; then
          CODEX_MISSING=$((CODEX_MISSING + 1))
        fi
      done < <(printf '%s' "$EXPANDED_TEMPLATE" | jq -r '.hooks[]?[]?.hooks[]?.command')
      if [ "$CODEX_MISSING" -gt 0 ]; then
        echo ""
        echo "  [missing] $CODEX_MISSING Codex hook(s) not registered in ~/.codex/hooks.json"
        echo "  To install, re-run: ./install.sh --register-hooks"
      fi
    fi
  fi
fi

exit 0
