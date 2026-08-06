#!/bin/sh
# task-runner.sh — CLI for the deploy task queue.
# Sources queue-lib.sh for all domain logic.
D="$(dirname "$0")"
. "$D/queue-lib.sh"

RUNNER_VERSION="1.0.0"

runner_banner() {
  printf 'task-runner v%s (queue-lib v%s)\n' "$RUNNER_VERSION" "$QUEUE_VERSION"
}

runner_create() {
  name="$1"; pri="${2:-$QUEUE_DEFAULT_PRIORITY}"
  rec="$(task_create "$name" "$pri")"
  printf 'created: %s\n' "$name"
  printf '%s\n' "$rec"
}

runner_normalize() {
  task_make_id "$1"
}

runner_idempotent_check() {
  name="$1"
  first="$(task_make_id "$name")"
  second="$(task_make_id "$first")"
  if [ "$first" = "$second" ]; then
    printf 'idempotent: yes (%s)\n' "$first"
    return 0
  else
    printf 'idempotent: no (first=%s second=%s)\n' "$first" "$second"
    return 1
  fi
}

runner_format() {
  rec="$1"
  task_format "$rec"
}

runner_priority() {
  task_priority_label "$1"
}

runner_validate_status() {
  if task_status_valid "$1"; then
    echo "valid"
  else
    echo "invalid"
  fi
}

runner_pipeline() {
  queue_new
  for name in "$@"; do
    queue_add "$name"
  done
  queue_summary
}

runner_help() {
  cat <<'HELP'
usage: task-runner.sh <command> [args...]
commands:
  banner                    — print version banner
  create <name> [priority]  — create a task record
  normalize <name>          — normalize a task name to an ID
  idempotent <name>         — check if normalize is idempotent
  format <record>           — format a task record for display
  priority <number>         — print priority label
  validate <status>         — check if status is valid
  pipeline <name...>        — run a mini pipeline
  help                      — this message
HELP
}

case "${1:-help}" in
  banner)     runner_banner ;;
  create)     runner_create "$2" "${3:-}" ;;
  normalize)  runner_normalize "$2" ;;
  idempotent) runner_idempotent_check "$2" ;;
  format)     runner_format "$2" ;;
  priority)   runner_priority "$2" ;;
  validate)   runner_validate_status "$2" ;;
  pipeline)   shift; runner_pipeline "$@" ;;
  help)       runner_help ;;
  *)          echo "unknown command: $1" >&2; exit 1 ;;
esac
