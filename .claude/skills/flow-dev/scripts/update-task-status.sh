#!/bin/bash
# update-task-status.sh — update a task's status in .flow-dev-lock.
# Usage: update-task-status.sh <task_id> <status>
# task_id: ticket slug or task number (must match .tasks[].id in lock)
# status: pending | in_progress | completed | failed
# Exit: 0=ok, 1=error (lock missing, task not found, invalid status)

set -euo pipefail

TASK_ID="${1:?Usage: update-task-status.sh <task_id> <status>}"
STATUS="${2:?Usage: update-task-status.sh <task_id> <status>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=flow-dev/scripts/lock.sh
. "$SCRIPT_DIR/lock.sh"

fd_lock_update_status "$TASK_ID" "$STATUS" || exit 1

echo "updated $TASK_ID → $STATUS"
