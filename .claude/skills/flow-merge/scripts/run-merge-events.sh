#!/usr/bin/env bash
# Run named flow-merge events from one or more TSV registries.
# Exit: 0=all requested events ran/skipped cleanly, 1=event failure/blocked dependent, 2=bad args/schema.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: run-merge-events.sh --phase <pre_merge|post_merge> --events <a,b> [--registry <path> ...] [--report <path>] [--prior-report <path>] [--confirm-user-gates|--confirm-user-gates-only]

Registry TSV columns:
  name<TAB>phase<TAB>implementation<TAB>needs<TAB>gate

Implementation forms:
  script:<repo-relative-or-absolute-path>
  skill:<skill-name>

Options:
  --prior-report <path>       Seed previously ran event statuses for isolated reruns.
  --confirm-user-gates        Prompt once for all requested gate:user events before execution.
  --confirm-user-gates-only   Prompt once, then exit without running events.

Env:
  FLOW_MERGE_SKILL_DISPATCHER  Required for skill:<name> events; invoked as: <command> <skill-name>.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PHASE=""
EVENTS_CSV=""
REPORT=""
REGISTRIES=()
PRIOR_REPORTS=()
CONFIRM_USER_GATES=0
CONFIRM_USER_GATES_ONLY=0
TERMINAL_EVENTS_CSV="${FLOW_MERGE_TERMINAL_EVENTS:-ticket-done}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      PHASE="${2:-}"; shift 2 ;;
    --events)
      EVENTS_CSV="${2:-}"; shift 2 ;;
    --registry)
      REGISTRIES+=("${2:-}"); shift 2 ;;
    --report)
      REPORT="${2:-}"; shift 2 ;;
    --prior-report)
      PRIOR_REPORTS+=("${2:-}"); shift 2 ;;
    --confirm-user-gates)
      CONFIRM_USER_GATES=1; shift ;;
    --confirm-user-gates-only)
      CONFIRM_USER_GATES=1
      CONFIRM_USER_GATES_ONLY=1
      shift ;;
    -h|--help)
      usage; exit 2 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage; exit 2 ;;
  esac
done

if [[ -z "$PHASE" || -z "$EVENTS_CSV" ]]; then
  usage; exit 2
fi
if [[ "$PHASE" != "pre_merge" && "$PHASE" != "post_merge" ]]; then
  echo "ERROR: phase must be pre_merge or post_merge (got: $PHASE)" >&2
  exit 2
fi
if [[ "${#REGISTRIES[@]}" -eq 0 ]]; then
  REGISTRIES=("$REPO_ROOT/flow-merge/references/merge-events.tsv")
fi

EVENT_NAMES=()
EVENT_PHASES=()
EVENT_IMPLS=()
EVENT_NEEDS_LIST=()
EVENT_GATES=()

event_index() {
  local event="$1" i
  for ((i = 0; i < ${#EVENT_NAMES[@]}; i++)); do
    [[ "${EVENT_NAMES[$i]}" == "$event" ]] && { printf '%s\n' "$i"; return 0; }
  done
  return 1
}

event_add() {
  local name="$1" phase="$2" implementation="$3" needs="$4" gate="$5"
  EVENT_NAMES+=("$name")
  EVENT_PHASES+=("$phase")
  EVENT_IMPLS+=("$implementation")
  EVENT_NEEDS_LIST+=("$needs")
  EVENT_GATES+=("$gate")
}

event_field() {
  local event="$1" field="$2" idx
  idx="$(event_index "$event")" || return 1
  case "$field" in
    phase) printf '%s\n' "${EVENT_PHASES[$idx]}" ;;
    implementation) printf '%s\n' "${EVENT_IMPLS[$idx]}" ;;
    needs) printf '%s\n' "${EVENT_NEEDS_LIST[$idx]}" ;;
    gate) printf '%s\n' "${EVENT_GATES[$idx]}" ;;
    *) return 1 ;;
  esac
}

STATUS_NAMES=()
STATUS_VALUES=()

status_set() {
  local event="$1" status="$2" i
  for ((i = 0; i < ${#STATUS_NAMES[@]}; i++)); do
    if [[ "${STATUS_NAMES[$i]}" == "$event" ]]; then
      STATUS_VALUES[$i]="$status"
      return 0
    fi
  done
  STATUS_NAMES+=("$event")
  STATUS_VALUES+=("$status")
}

status_get() {
  local event="$1" i
  for ((i = 0; i < ${#STATUS_NAMES[@]}; i++)); do
    [[ "${STATUS_NAMES[$i]}" == "$event" ]] && { printf '%s\n' "${STATUS_VALUES[$i]}"; return 0; }
  done
  return 1
}

contains_event() {
  local needle="$1"; shift
  local event
  for event in "$@"; do
    [[ "$event" == "$needle" ]] && return 0
  done
  return 1
}

load_registry() {
  local registry="$1"
  [[ -f "$registry" ]] || { echo "ERROR: registry not found: $registry" >&2; exit 2; }

  local line row name phase implementation needs gate
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    row="${line//$'\t'/$'\x1f'}"
    IFS=$'\x1f' read -r name phase implementation needs gate _extra <<<"$row"
    [[ "$name" == "name" ]] && continue
    if [[ -z "${name:-}" || -z "${phase:-}" || -z "${implementation:-}" || -z "${gate:-}" ]]; then
      echo "ERROR: malformed registry row in $registry: $line" >&2
      exit 2
    fi
    event_add "$name" "$phase" "$implementation" "${needs:-}" "$gate"
  done < "$registry"
}

for registry in "${REGISTRIES[@]}"; do
  load_registry "$registry"
done

IFS=',' read -r -a REQUESTED <<<"$EVENTS_CSV"

if [[ -z "$REPORT" ]]; then
  REPORT="$(mktemp)"
fi
: > "$REPORT"
printf 'event\tphase\tstatus\tdetail\n' >> "$REPORT"

TERMINAL_EVENTS=()
EXECUTION_ORDER=()
had_failure=0

for event in "${REQUESTED[@]}"; do
  event="${event//[[:space:]]/}"
  [[ -z "$event" ]] && continue
done

IFS=',' read -r -a TERMINAL_LIST <<<"$TERMINAL_EVENTS_CSV"
for event in "${TERMINAL_LIST[@]}"; do
  event="${event//[[:space:]]/}"
  [[ -z "$event" ]] && continue
  TERMINAL_EVENTS+=("$event")
done

build_execution_order() {
  local event
  EXECUTION_ORDER=()
  if [[ "$PHASE" != "post_merge" ]]; then
    EXECUTION_ORDER=("${REQUESTED[@]}")
    return 0
  fi
  for event in "${REQUESTED[@]}"; do
    event="${event//[[:space:]]/}"
    [[ -z "$event" ]] && continue
    contains_event "$event" ${TERMINAL_EVENTS+"${TERMINAL_EVENTS[@]}"} && continue
    EXECUTION_ORDER+=("$event")
  done
  for event in "${REQUESTED[@]}"; do
    event="${event//[[:space:]]/}"
    [[ -z "$event" ]] && continue
    contains_event "$event" ${TERMINAL_EVENTS+"${TERMINAL_EVENTS[@]}"} || continue
    EXECUTION_ORDER+=("$event")
  done
}

load_prior_report() {
  local report="$1" line event phase status _detail
  [[ -f "$report" ]] || { echo "ERROR: prior report not found: $report" >&2; exit 2; }
  while IFS=$'\t' read -r event phase status _detail || [[ -n "${event:-}" ]]; do
    [[ -z "${event:-}" || "$event" == "event" ]] && continue
    if [[ "$phase" == "$PHASE" && "$status" == "ran" ]]; then
      status_set "$event" "ran"
    fi
  done < "$report"
}

for prior_report in ${PRIOR_REPORTS+"${PRIOR_REPORTS[@]}"}; do
  load_prior_report "$prior_report"
done

validate_requested_events() {
  local event="$1" event_phase
  if ! event_field "$event" implementation >/dev/null; then
    printf '%s\t%s\tfailed\t%s\n' "$event" "$PHASE" "unregistered event" >> "$REPORT"
    status_set "$event" "failed"
    had_failure=1
    return 1
  fi
  event_phase="$(event_field "$event" phase)"
  if [[ "$event_phase" != "$PHASE" ]]; then
    printf '%s\t%s\tfailed\t%s\n' "$event" "$PHASE" "registered for $event_phase" >> "$REPORT"
    status_set "$event" "failed"
    had_failure=1
    return 1
  fi
  return 0
}

confirm_user_gates() {
  local event event_phase event_gate gated=() answer
  for event in "${REQUESTED[@]}"; do
    event="${event//[[:space:]]/}"
    [[ -z "$event" ]] && continue
    event_phase="$(event_field "$event" phase 2>/dev/null || true)"
    event_gate="$(event_field "$event" gate 2>/dev/null || true)"
    [[ "$event_phase" == "$PHASE" && "$event_gate" == "user" ]] && gated+=("$event")
  done

  if [[ "${#gated[@]}" -eq 0 ]]; then
    [[ "$CONFIRM_USER_GATES_ONLY" -eq 1 ]] && echo "OK: no user-gated events enabled"
    return 0
  fi
  if [[ "${FLOW_MERGE_USER_GATES_CONFIRMED:-0}" == "1" ]]; then
    [[ "$CONFIRM_USER_GATES_ONLY" -eq 1 ]] && printf 'OK: user-gated events already confirmed: %s\n' "${gated[*]}"
    return 0
  fi

  echo "flow-merge will run user-gated events:" >&2
  for event in "${gated[@]}"; do
    printf '  - %s\n' "$event" >&2
  done
  printf 'Confirm these events now? [y/N] ' >&2
  IFS= read -r answer
  case "$answer" in
    y|Y|yes|YES)
      export FLOW_MERGE_USER_GATES_CONFIRMED=1
      ;;
    *)
      echo "ERROR: user-gated events were not confirmed" >&2
      return 1
      ;;
  esac
}

has_blocked_need() {
  local event="$1" needs need need_status
  needs="$(event_field "$event" needs 2>/dev/null || true)"
  [[ -z "$needs" ]] && return 1
  IFS=',' read -r -a need_list <<<"$needs"
  for need in "${need_list[@]}"; do
    need="${need//[[:space:]]/}"
    [[ -z "$need" ]] && continue
    need_status="$(status_get "$need" 2>/dev/null || true)"
    if [[ "$need_status" != "ran" ]]; then
      return 0
    fi
  done
  return 1
}

resolve_script_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$REPO_ROOT" "$path"
  fi
}

run_event() {
  local event="$1" implementation="$2"
  case "$implementation" in
    script:*)
      local script_path="${implementation#script:}"
      script_path="$(resolve_script_path "$script_path")"
      [[ -f "$script_path" ]] || { echo "script not found: $script_path" >&2; return 127; }
      bash "$script_path"
      ;;
    skill:*)
      local skill_name="${implementation#skill:}"
      if [[ -n "${FLOW_MERGE_SKILL_DISPATCHER:-}" ]]; then
        "$FLOW_MERGE_SKILL_DISPATCHER" "$skill_name"
      else
        echo "skill event requires FLOW_MERGE_SKILL_DISPATCHER: $skill_name" >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported implementation for $event: $implementation" >&2
      return 2
      ;;
  esac
}

build_execution_order

if [[ "$CONFIRM_USER_GATES" -eq 1 ]]; then
  for event in "${REQUESTED[@]}"; do
    event="${event//[[:space:]]/}"
    [[ -z "$event" ]] && continue
    validate_requested_events "$event" || true
  done
  if [[ "$had_failure" -eq 0 ]]; then
    if ! confirm_user_gates; then
      for event in "${REQUESTED[@]}"; do
        event="${event//[[:space:]]/}"
        [[ -z "$event" ]] && continue
        if [[ "$(event_field "$event" phase 2>/dev/null || true)" == "$PHASE" && "$(event_field "$event" gate 2>/dev/null || true)" == "user" ]]; then
          printf '%s\t%s\tfailed\t%s\n' "$event" "$PHASE" "user gate not confirmed up front" >> "$REPORT"
        fi
      done
      had_failure=1
    fi
  fi
  if [[ "$CONFIRM_USER_GATES_ONLY" -eq 1 ]]; then
    cat "$REPORT"
    [[ "$had_failure" -eq 0 ]] || exit 1
    exit 0
  fi
fi

for event in "${EXECUTION_ORDER[@]}"; do
  event="${event//[[:space:]]/}"
  [[ -z "$event" ]] && continue

  if ! validate_requested_events "$event"; then
    continue
  fi
  if [[ "$PHASE" == "post_merge" ]] && contains_event "$event" ${TERMINAL_EVENTS+"${TERMINAL_EVENTS[@]}"} && [[ "$had_failure" -ne 0 ]]; then
    printf '%s\t%s\tskipped-due-to-needs\t%s\n' "$event" "$PHASE" "prior post-merge event failed" >> "$REPORT"
    status_set "$event" "skipped-due-to-needs"
    had_failure=1
    continue
  fi
  if [[ "$(event_field "$event" gate)" == "user" && "${FLOW_MERGE_USER_GATES_CONFIRMED:-0}" != "1" ]]; then
    printf '%s\t%s\tfailed\t%s\n' "$event" "$PHASE" "user gate not confirmed up front" >> "$REPORT"
    status_set "$event" "failed"
    had_failure=1
    continue
  fi
  if has_blocked_need "$event"; then
    printf '%s\t%s\tskipped-due-to-needs\t%s\n' "$event" "$PHASE" "dependency did not run successfully" >> "$REPORT"
    status_set "$event" "skipped-due-to-needs"
    had_failure=1
    continue
  fi

  if output=$(run_event "$event" "$(event_field "$event" implementation)" 2>&1); then
    printf '%s\t%s\tran\t%s\n' "$event" "$PHASE" "${output//$'\n'/; }" >> "$REPORT"
    status_set "$event" "ran"
  else
    rc=$?
    printf '%s\t%s\tfailed\t%s\n' "$event" "$PHASE" "rc=$rc ${output//$'\n'/; }" >> "$REPORT"
    status_set "$event" "failed"
    had_failure=1
  fi
done

cat "$REPORT"
if [[ "$had_failure" -ne 0 ]]; then
  exit 1
fi
exit 0
