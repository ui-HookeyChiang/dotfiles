#!/usr/bin/env bash
# Extractor adapter: claude (reference agent)
# Interface: extract_denies, extract_docs, extract_hooks, extract_agent_defs,
#            extract_model, extract_resolve_doc_path

extract_denies() {
  local settings="$1"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '.permissions.deny[]?' "$settings" 2>/dev/null \
    | sed 's/Bash(//;s/)$//;s/:\*$//;s/ \*$//' | sort -u
}

extract_docs() {
  local _settings="$1" instructions="$2"
  [ -n "$instructions" ] && [ -f "$instructions" ] || return 0
  local real_instr="$instructions"
  [ -L "$real_instr" ] && real_instr="$(readlink -f "$real_instr")"
  rg '^@' "$real_instr" 2>/dev/null | sed 's/^@//;s|.*/||' | sort
}

extract_hooks() {
  local settings="$1"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '[.hooks[]?[]?.hooks[]?.command // empty] | .[]' "$settings" 2>/dev/null \
    | sed 's|.*/||;s/\.sh$//;s/^rtk hook claude$/rtk/;s/^bash //' | sort -u
}

extract_agent_defs() {
  local _settings="$1"
  local agents_dir="$HOME/.claude/agents"
  [ -d "$agents_dir" ] || return 0
  ls "$agents_dir"/*.md 2>/dev/null | xargs -I{} basename {} | sed 's/\.md$//' | sort -u
}

extract_model() {
  local settings="$1"
  [ -n "$settings" ] && [ -f "$settings" ] || return 0
  jq -r '.model // empty' "$settings" 2>/dev/null
}

extract_resolve_doc_path() {
  local _settings="$1" instructions="$2" doc="$3"
  [ -n "$instructions" ] && [ -f "$instructions" ] || return 0
  local real_instr="$instructions"
  [ -L "$real_instr" ] && real_instr="$(readlink -f "$real_instr")"
  local base_dir
  base_dir="$(dirname "$real_instr")"
  local ref
  ref=$(rg "^@.*${doc}$" "$real_instr" 2>/dev/null | head -1 | sed 's/^@//')
  [ -n "$ref" ] && echo "$base_dir/$ref"
}
