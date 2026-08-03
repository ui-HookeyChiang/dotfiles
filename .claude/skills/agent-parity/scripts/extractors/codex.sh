#!/usr/bin/env bash
# Extractor adapter: codex

extract_denies() {
  local _settings="$1"
  local permissions="${EXTRACTOR_PERMISSIONS_FILE:-}"
  [ -n "$permissions" ] && [ -f "$permissions" ] || return 0
  jq -r '.permissions.deny[]?' "$permissions" 2>/dev/null \
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
  local _settings="$1"
  local hooks_file="${EXTRACTOR_HOOKS_FILE:-}"
  [ -n "$hooks_file" ] && [ -f "$hooks_file" ] || return 0
  jq -r '[.hooks[]?[]?.hooks[]?.command // empty] | .[]' "$hooks_file" 2>/dev/null \
    | sed 's|.*/||;s/\.sh$//;s/^bash //;s/^rtk hook claude$/rtk/' | sort -u
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
  python3 - "$settings" <<'PY' 2>/dev/null || true
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    print(tomllib.load(f).get("model", ""))
PY
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
