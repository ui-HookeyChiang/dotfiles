#!/usr/bin/env bash
# Validate merge-event registry rows and dependency references.
# Exit: 0=ok, 1=lint failure, 2=bad invocation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

REGISTRIES=()
MERGE_CONFIGS=()
explicit_args=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry)
      REGISTRIES+=("${2:-}")
      explicit_args=1
      shift 2
      ;;
    --merge-config)
      MERGE_CONFIGS+=("${2:-}")
      explicit_args=1
      shift 2
      ;;
    -h|--help)
      echo "Usage: lint-merge-events.sh [--registry <path>]... [--merge-config <path>]... [registry ...]" >&2
      exit 2
      ;;
    --*)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
    *)
      REGISTRIES+=("$1")
      explicit_args=1
      shift
      ;;
  esac
done

if [[ "${#REGISTRIES[@]}" -eq 0 ]]; then
  while IFS= read -r registry; do
    REGISTRIES+=("$registry")
  done < <(cd "$REPO_ROOT" && find . -path '*/references/merge-events.tsv' \
    -not -path './.git/*' \
    -not -path './.worktree/*' \
    -not -path './.worktrees/*' \
    -print | sort)
fi

if [[ "$explicit_args" -eq 0 && "${#MERGE_CONFIGS[@]}" -eq 0 ]]; then
  while IFS= read -r config; do
    MERGE_CONFIGS+=("$config")
  done < <(cd "$REPO_ROOT" && find . -path '*/references/merge-config.md' \
    -not -path './.git/*' \
    -not -path './.worktree/*' \
    -not -path './.worktrees/*' \
    -print | sort)
fi

if [[ "${#REGISTRIES[@]}" -eq 0 ]]; then
  echo "ERROR: no merge-event registries found" >&2
  exit 1
fi

EVENT_NAMES=()
EVENT_REGISTRIES=()
EVENT_PHASES=()
EVENT_NEEDS_LIST=()
failures=0

fail() {
  failures=$((failures + 1))
  echo "  FAIL: $*" >&2
}

event_index() {
  local event="$1" i
  for ((i = 0; i < ${#EVENT_NAMES[@]}; i++)); do
    [[ "${EVENT_NAMES[$i]}" == "$event" ]] && { printf '%s\n' "$i"; return 0; }
  done
  return 1
}

event_add() {
  local registry="$1" name="$2" phase="$3" needs="$4"
  EVENT_NAMES+=("$name")
  EVENT_REGISTRIES+=("$registry")
  EVENT_PHASES+=("$phase")
  EVENT_NEEDS_LIST+=("$needs")
}

event_registry() {
  local idx
  idx="$(event_index "$1")" || return 1
  printf '%s\n' "${EVENT_REGISTRIES[$idx]}"
}

event_phase() {
  local idx
  idx="$(event_index "$1")" || return 1
  printf '%s\n' "${EVENT_PHASES[$idx]}"
}

resolve_script_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$REPO_ROOT" "$path"
  fi
}

load_and_check_row() {
  local registry="$1" line="$2"
  local row name phase implementation needs gate
  row="${line//$'\t'/$'\x1f'}"
  IFS=$'\x1f' read -r name phase implementation needs gate _extra <<<"$row"
  [[ "$name" == "name" ]] && return 0

  if [[ -z "${name:-}" || -z "${phase:-}" || -z "${implementation:-}" || -z "${gate:-}" ]]; then
    fail "$registry: malformed row: $line"
    return 0
  fi
  if [[ "$name" =~ [^a-z0-9-] ]]; then
    fail "$registry: event '$name' must be kebab-case"
  fi
  if [[ "$phase" != "pre_merge" && "$phase" != "post_merge" ]]; then
    fail "$registry: event '$name' has invalid phase '$phase'"
  fi
  if [[ "$gate" != "none" && "$gate" != "user" ]]; then
    fail "$registry: event '$name' has invalid gate '$gate'"
  fi
  if event_index "$name" >/dev/null; then
    fail "$registry: duplicate event '$name' also declared in $(event_registry "$name")"
  fi
  event_add "$registry" "$name" "$phase" "${needs:-}"

  case "$implementation" in
    script:*)
      local script_path="${implementation#script:}"
      script_path="$(resolve_script_path "$script_path")"
      [[ -f "$script_path" ]] || fail "$registry: event '$name' script not found: $script_path"
      ;;
    skill:*)
      local skill_name="${implementation#skill:}"
      [[ -d "$REPO_ROOT/$skill_name" ]] || fail "$registry: event '$name' skill not found: $skill_name"
      ;;
    *)
      fail "$registry: event '$name' has unsupported implementation '$implementation'"
      ;;
  esac
}

for registry in "${REGISTRIES[@]}"; do
  registry="${registry#./}"
  registry_path="$registry"
  [[ "$registry_path" = /* ]] || registry_path="$REPO_ROOT/$registry_path"
  if [[ ! -f "$registry_path" ]]; then
    fail "registry not found: $registry"
    continue
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    load_and_check_row "$registry" "$line"
  done < "$registry_path"
done

trim_spaces() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

check_merge_config_event() {
  local config="$1" line_no="$2" phase="$3" event="$4"
  event="$(trim_spaces "$event")"
  event="${event%\"}"
  event="${event#\"}"
  event="${event%\'}"
  event="${event#\'}"
  [[ -z "$event" ]] && return 0
  if ! event_index "$event" >/dev/null; then
    fail "$config:$line_no: unknown $phase event '$event'"
    return 0
  fi
  if [[ "$(event_phase "$event")" != "$phase" ]]; then
    fail "$config:$line_no: event '$event' is $(event_phase "$event"), not $phase"
  fi
}

check_merge_config_list() {
  local config="$1" line_no="$2" field="$3" value="$4" phase
  case "$field" in
    pre_merge_events) phase="pre_merge" ;;
    post_merge_events) phase="post_merge" ;;
    *) return 0 ;;
  esac
  value="$(trim_spaces "$value")"
  if [[ ! "$value" =~ ^\[[^]]*\]$ ]]; then
    fail "$config:$line_no: $field must be a uniform YAML list, got '$value'"
    return 0
  fi
  value="${value#\[}"
  value="${value%\]}"
  [[ -z "$(trim_spaces "$value")" ]] && return 0
  IFS=',' read -r -a config_events <<<"$value"
  for event in "${config_events[@]}"; do
    check_merge_config_event "$config" "$line_no" "$phase" "$event"
  done
}

check_merge_config() {
  local config="$1" config_path="$1" line_no=0 line field value
  [[ "$config_path" = /* ]] || config_path="$REPO_ROOT/${config#./}"
  if [[ ! -f "$config_path" ]]; then
    fail "merge config not found: $config"
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    if [[ "$line" =~ (^|[[:space:]])pre_merge_hook: || "$line" =~ (^|[[:space:]])post_merge_hook: ]]; then
      fail "$config:$line_no: use pre_merge_events/post_merge_events lists, not hook strings"
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*(pre_merge_events|post_merge_events):[[:space:]]*(.*)$ ]]; then
      field="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      check_merge_config_list "$config" "$line_no" "$field" "$value"
    fi
  done < "$config_path"
}

for config in ${MERGE_CONFIGS+"${MERGE_CONFIGS[@]}"}; do
  check_merge_config "$config"
done

for ((event_idx = 0; event_idx < ${#EVENT_NAMES[@]}; event_idx++)); do
  event="${EVENT_NAMES[$event_idx]}"
  needs="${EVENT_NEEDS_LIST[$event_idx]}"
  [[ -z "$needs" ]] && continue
  IFS=',' read -r -a need_list <<<"$needs"
  for need in "${need_list[@]}"; do
    need="${need//[[:space:]]/}"
    [[ -z "$need" ]] && continue
    event_index "$need" >/dev/null || fail "${EVENT_REGISTRIES[$event_idx]}: event '$event' needs unknown event '$need'"
  done
done

if [[ "$failures" -gt 0 ]]; then
  echo "merge-event registry lint: $failures failure(s)" >&2
  exit 1
fi

echo "merge-event registry lint: OK (${#EVENT_NAMES[@]} events, ${#MERGE_CONFIGS[@]} merge configs)"
exit 0
