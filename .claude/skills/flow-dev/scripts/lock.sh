#!/usr/bin/env bash
# lock.sh — shared .flow-dev-lock operations for flow-dev scripts.

fd_lock_file() {
  echo "${FLOW_DEV_LOCK_FILE:-.flow-dev-lock}"
}

fd_lock_source_parallel_layers() {
  local script_dir repo_root
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "$script_dir/../.." && pwd)"
  if [[ -f "$repo_root/_shared/stack/lib/parallel-layers.sh" ]]; then
    # shellcheck source=../../_shared/stack/lib/parallel-layers.sh
    . "$repo_root/_shared/stack/lib/parallel-layers.sh"
  fi
}

fd_lock_resolve_base_branch() {
  local feature_prefix="$1" task_n="$2" default_branch="$3" lock_file
  lock_file="$(fd_lock_file)"

  local lock_layers
  lock_layers=$(jq -c '.parallel_layers // null' "$lock_file" 2>/dev/null || echo null)
  if [[ "$lock_layers" == "null" ]]; then
    [[ "$task_n" -eq 1 ]] && FD_LOCK_BASE_BRANCH="$default_branch" || FD_LOCK_BASE_BRANCH="${feature_prefix}/task-$((task_n-1))"
    FD_LOCK_TASK_BRANCH="${feature_prefix}/task-${task_n}"
    return 0
  fi

  if [[ "$lock_layers" == "[]" ]]; then
    echo "[STOP-SAFE] .flow-dev-lock.parallel_layers is empty array — lock corruption." >&2
    return 1
  fi

  fd_lock_source_parallel_layers
  if ! type pl_layer_of >/dev/null 2>&1; then
    echo "[STOP-SAFE] parallel_layers declared but parallel-layers.sh not sourceable." >&2
    return 1
  fi

  local group_id layer
  group_id="${SD_GROUP_ID:-PR-${task_n}}"
  layer=$(pl_layer_of "$lock_layers" "$group_id" 2>&1) || {
    echo "[STOP-SAFE] GROUP_ID '${group_id}' not found in parallel_layers." >&2
    return 1
  }

  if [[ "$layer" == "1" ]]; then
    FD_LOCK_BASE_BRANCH="$default_branch"
  else
    FD_LOCK_BASE_BRANCH="${feature_prefix}/task-$(pl_first_in_layer "$lock_layers" "$((layer - 1))")"
  fi
  FD_LOCK_TASK_BRANCH="${feature_prefix}/task-${group_id}"
}

fd_lock_assert_unblocked() {
  local task_id="$1" blocked_by_json="$2" lock_file blocker blocker_status
  lock_file="$(fd_lock_file)"

  [[ "$blocked_by_json" != "[]" ]] || return 0

  local unmet=()
  for blocker in $(echo "$blocked_by_json" | jq -r '.[]'); do
    blocker_status=""
    if [[ -f "$lock_file" ]]; then
      blocker_status=$(jq -r --arg tp "$blocker"         '(.tasks // [])[] | select(.ticket_path == $tp) | .status'         "$lock_file" 2>/dev/null || echo "")
    fi
    if [[ "$blocker_status" != "completed" ]]; then
      unmet+=("$blocker (status: ${blocker_status:-not registered})")
    fi
  done

  if [[ ${#unmet[@]} -gt 0 ]]; then
    echo "[STOP-SAFE] Task $task_id blocked by unfinished dependencies:" >&2
    local u
    for u in "${unmet[@]}"; do
      echo "  - $u" >&2
    done
    return 1
  fi
}

fd_lock_register_task() {
  local task_id="$1" ticket_path="$2" blocked_by_json="$3" lock_file tmp
  lock_file="$(fd_lock_file)"

  if [[ -f "$lock_file" ]]; then
    tmp="${lock_file}.tmp"
    jq --arg id "$task_id" --arg tp "$ticket_path" --argjson bb "$blocked_by_json"       'if .tasks then
         if (.tasks | map(.id) | index($id)) then
           (.tasks[] | select(.id == $id)) |= (.ticket_path = $tp | .blocked_by = $bb)
         else
           .tasks += [{"id": $id, "ticket_path": $tp, "blocked_by": $bb, "status": "pending"}]
         end
       else
         .tasks = [{"id": $id, "ticket_path": $tp, "blocked_by": $bb, "status": "pending"}]
       end' "$lock_file" > "$tmp"       && mv "$tmp" "$lock_file"
  else
    printf '{"tasks":[{"id":"%s","ticket_path":"%s","blocked_by":%s,"status":"pending"}]}
'       "$task_id" "$ticket_path" "$blocked_by_json" > "$lock_file"
  fi
}

fd_lock_register_ticket_task() {
  local task_id="$1" ticket_path="$2" script_dir blocked_by
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  blocked_by=$(bash "$script_dir/parse-blocked-by.sh" "$ticket_path") || return 1
  fd_lock_assert_unblocked "$task_id" "$blocked_by" || return 1
  fd_lock_register_task "$task_id" "$ticket_path" "$blocked_by"
  FD_LOCK_BLOCKED_BY="$blocked_by"
}

fd_lock_update_status() {
  local task_id="$1" status="$2" lock_file tmp
  lock_file="$(fd_lock_file)"

  case "$status" in
    pending|in_progress|completed|failed) ;;
    *) echo "[STOP-SAFE] Invalid status '$status'. Must be: pending|in_progress|completed|failed" >&2; return 1 ;;
  esac

  if [[ ! -f "$lock_file" ]]; then
    echo "[STOP-SAFE] No .flow-dev-lock in $(pwd)" >&2
    return 1
  fi

  if ! jq -e --arg id "$task_id" '.tasks[]? | select(.id == $id)' "$lock_file" >/dev/null 2>&1; then
    echo "[STOP-SAFE] Task '$task_id' not found in .flow-dev-lock" >&2
    return 1
  fi

  tmp="${lock_file}.tmp"
  jq --arg id "$task_id" --arg status "$status"     '(.tasks[] | select(.id == $id)).status = $status'     "$lock_file" > "$tmp"     && mv "$tmp" "$lock_file"
}
