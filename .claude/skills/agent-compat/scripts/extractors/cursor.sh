#!/usr/bin/env bash
# Extractor adapter: cursor

extract_denies() {
  local settings="$1"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '.permissions.deny[]?' "$settings" 2>/dev/null \
    | sed 's/^Shell(//;s/^Bash(//;s/)$//;s/:\*$//;s/ \*$//' | sort -u
}

extract_docs() {
  # reason: Cursor User Rules are settings-only (no file-backed doc surface);
  #   AGENTS.md/CLAUDE.md are read at project root only, not user level.
  # verified: 2026-08-03
  # review-by: 2027-02-03
  return 0
}

extract_hooks() {
  local _settings="$1"
  local hooks_file="${EXTRACTOR_HOOKS_FILE:-}"
  [ -n "$hooks_file" ] && [ -f "$hooks_file" ] || return 0
  jq -r '[.hooks[]?[].command // empty] | .[]' "$hooks_file" 2>/dev/null \
    | sed 's|.*/||;s/\.sh$//;s/^bash //;s/^rtk hook cursor$/rtk/' | sort -u
}

extract_agent_defs() {
  local _settings="$1"
  local agents_dir="${EXTRACTOR_AGENT_DEFS_DIR:-}"
  [ -n "$agents_dir" ] && [ -d "$agents_dir" ] || return 0
  ls "$agents_dir"/*.md 2>/dev/null | xargs -I{} basename {} | sed 's/\.md$//' | sort -u
}

extract_model() {
  local settings="$1"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '.model.displayModelId // empty' "$settings" 2>/dev/null
}

extract_skills() {
  # reason: Cursor custom-skill loading surface is unverified; only built-in
  #   skills-cursor exists, with no confirmed user-skill directory contract.
  # verified: 2026-08-03
  # review-by: 2027-02-03
  return 0
}

extract_resolve_doc_path() {
  # reason: Cursor User Rules are settings-only (no file-backed doc surface);
  #   AGENTS.md/CLAUDE.md are read at project root only, not user level.
  # verified: 2026-08-03
  # review-by: 2027-02-03
  return 0
}
