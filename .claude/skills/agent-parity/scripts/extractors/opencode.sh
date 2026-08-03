#!/usr/bin/env bash
# Extractor adapter: opencode

extract_denies() {
  local settings="$1"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '.permission.bash | to_entries[] | select(.value=="deny") | .key' "$settings" 2>/dev/null \
    | sed 's/ \*$//' | sort -u
}

extract_docs() {
  local settings="$1" _instructions="$2"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '.instructions[]?' "$settings" 2>/dev/null | sed 's|.*/||' | sort
}

extract_hooks() {
  local _settings="$1"
  local hooks_dir
  hooks_dir="${EXTRACTOR_HOOKS_DIR:-}"
  [ -n "$hooks_dir" ] && [ -d "$hooks_dir" ] || return 0
  ls "$hooks_dir"/*.js "$hooks_dir"/*.ts 2>/dev/null \
    | xargs -I{} basename {} | sed -E 's/\.(js|ts)$//' | sort -u
  local plugin_file
  for plugin_file in "$hooks_dir"/*.js "$hooks_dir"/*.ts; do
    [ -f "$plugin_file" ] || continue
    rg -q 'block-main-edit\.sh' "$plugin_file" 2>/dev/null && echo "block-main-edit"
    rg -q 'block-bare-read\.sh' "$plugin_file" 2>/dev/null && echo "block-bare-read"
    rg -q 'guard-agent-worktree\.sh' "$plugin_file" 2>/dev/null && echo "guard-agent-worktree"
    rg -q 'guard-stale-base\.sh' "$plugin_file" 2>/dev/null && echo "guard-stale-base"
  done
  local agents_dir
  agents_dir="$(dirname "$hooks_dir")/agents"
  if [ -d "$agents_dir" ]; then
    rg -ql 'Delivery Red Lines' "$agents_dir"/*.md 2>/dev/null && echo "subagent-dispatch-inject"
  fi
}

extract_agent_defs() {
  local settings="$1"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '.agent // {} | keys[]?' "$settings" 2>/dev/null | sort -u
}

extract_model() {
  local settings="$1"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '.model // empty' "$settings" 2>/dev/null
}

extract_resolve_doc_path() {
  local settings="$1" _instructions="$2" doc="$3"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  local path
  path=$(jq -r ".instructions[]? | select(endswith(\"$doc\"))" "$settings" 2>/dev/null | head -1)
  [ -n "$path" ] && eval echo "$path"
}
