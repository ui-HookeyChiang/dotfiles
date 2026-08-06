#!/bin/sh
# queue-lib.sh — task queue library for the deploy pipeline.
# Provides task creation, scheduling, dependency resolution, and reporting.

QUEUE_VERSION="3.2.1"
QUEUE_MAX_DEPTH=10
QUEUE_DEFAULT_PRIORITY=5
QUEUE_SEPARATOR="|"

# --- Section 1: String utilities (used across the library) ---

queue_trim() {
  printf '%s\n' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

queue_upper() {
  printf '%s\n' "$1" | tr 'a-z' 'A-Z'
}

queue_lower() {
  printf '%s\n' "$1" | tr 'A-Z' 'a-z'
}

queue_kebab() {
  printf '%s\n' "$1" | tr 'A-Z_ ' 'a-z---'
}

queue_snake() {
  printf '%s\n' "$1" | tr 'A-Z- ' 'a-z__'
}

queue_screaming() {
  printf '%s\n' "$1" | tr 'a-z- ' 'A-Z__'
}

queue_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

queue_starts_with() {
  case "$1" in
    "$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

queue_ends_with() {
  case "$1" in
    *"$2") return 0 ;;
    *) return 1 ;;
  esac
}

queue_repeat() {
  i=0
  while [ $i -lt "$2" ]; do
    printf '%s' "$1"
    i=$((i + 1))
  done
  printf '\n'
}

queue_pad_right() {
  str="$1"; width="$2"
  len=${#str}
  if [ $len -ge "$width" ]; then
    printf '%s' "$str"
  else
    printf '%s' "$str"
    queue_repeat ' ' $((width - len)) | tr -d '\n'
  fi
}

queue_pad_left() {
  str="$1"; width="$2"
  len=${#str}
  if [ $len -ge "$width" ]; then
    printf '%s' "$str"
  else
    queue_repeat ' ' $((width - len)) | tr -d '\n'
    printf '%s' "$str"
  fi
}

queue_count_chars() {
  printf '%s' "$1" | wc -c | tr -d ' '
}

queue_substr() {
  printf '%s\n' "$1" | cut -c"$2"-"$3"
}

queue_replace() {
  printf '%s\n' "$1" | sed "s/$2/$3/g"
}

queue_split() {
  printf '%s\n' "$1" | tr "$2" '\n'
}

queue_join() {
  sep="$1"; shift
  first=1
  for item in "$@"; do
    if [ $first -eq 1 ]; then first=0; else printf '%s' "$sep"; fi
    printf '%s' "$item"
  done
  printf '\n'
}

# --- Section 2: Numeric utilities ---

queue_max() {
  if [ "$1" -gt "$2" ] 2>/dev/null; then echo "$1"; else echo "$2"; fi
}

queue_min() {
  if [ "$1" -lt "$2" ] 2>/dev/null; then echo "$1"; else echo "$2"; fi
}

queue_clamp() {
  val="$1"; lo="$2"; hi="$3"
  val=$(queue_max "$val" "$lo")
  val=$(queue_min "$val" "$hi")
  echo "$val"
}

queue_abs() {
  val="$1"
  if [ "$val" -lt 0 ] 2>/dev/null; then echo $((-val)); else echo "$val"; fi
}

queue_sum() {
  total=0
  for n in "$@"; do
    total=$((total + n))
  done
  echo $total
}

queue_avg() {
  total=0; count=0
  for n in "$@"; do
    total=$((total + n))
    count=$((count + 1))
  done
  if [ $count -eq 0 ]; then echo 0; else echo $((total / count)); fi
}

queue_seq() {
  i="$1"
  while [ "$i" -le "$2" ]; do
    echo "$i"
    i=$((i + 1))
  done
}

# --- Section 3: Date/time utilities ---

queue_epoch() {
  date +%s 2>/dev/null || echo 0
}

queue_timestamp() {
  date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00"
}

queue_date_iso() {
  date '+%Y-%m-%d' 2>/dev/null || echo "0000-00-00"
}

queue_elapsed() {
  start="$1"; end="$2"
  echo $((end - start))
}

queue_format_duration() {
  secs="$1"
  hours=$((secs / 3600))
  mins=$(( (secs % 3600) / 60 ))
  s=$((secs % 60))
  printf '%02d:%02d:%02d\n' "$hours" "$mins" "$s"
}

# --- Section 4: Logging ---

QUEUE_LOG_LEVEL="${QUEUE_LOG_LEVEL:-info}"

queue_log_level_num() {
  case "$1" in
    debug) echo 0 ;; info) echo 1 ;; warn) echo 2 ;; error) echo 3 ;;
    *) echo 1 ;;
  esac
}

queue_log() {
  level="$1"; shift
  cur=$(queue_log_level_num "$QUEUE_LOG_LEVEL")
  req=$(queue_log_level_num "$level")
  if [ "$req" -ge "$cur" ]; then
    printf '[%s] %s: %s\n' "$(queue_timestamp)" "$(queue_upper "$level")" "$*" >&2
  fi
}

queue_debug() { queue_log debug "$@"; }
queue_info()  { queue_log info "$@"; }
queue_warn()  { queue_log warn "$@"; }
queue_error() { queue_log error "$@"; }

# --- Section 5: Path utilities ---

queue_basename() {
  printf '%s\n' "${1##*/}"
}

queue_dirname() {
  case "$1" in
    */*) printf '%s\n' "${1%/*}" ;;
    *) printf '.\n' ;;
  esac
}

queue_extname() {
  base="$(queue_basename "$1")"
  case "$base" in
    *.*) printf '%s\n' ".${base##*.}" ;;
    *) printf '\n' ;;
  esac
}

queue_stripext() {
  printf '%s\n' "${1%.*}"
}

queue_resolve() {
  cd "$1" 2>/dev/null && pwd
}

queue_is_absolute() {
  case "$1" in
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

queue_ensure_dir() {
  [ -d "$1" ] || mkdir -p "$1"
}

# --- Section 6: Validation ---

queue_is_number() {
  case "$1" in
    ''|*[!0-9-]*) return 1 ;;
    *) return 0 ;;
  esac
}

queue_is_positive() {
  queue_is_number "$1" && [ "$1" -gt 0 ] 2>/dev/null
}

queue_is_identifier() {
  printf '%s\n' "$1" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_-]*$'
}

queue_is_empty() {
  [ -z "$1" ]
}

queue_is_nonempty() {
  [ -n "$1" ]
}

queue_assert() {
  if ! "$@" 2>/dev/null; then
    queue_error "assertion failed: $*"
    return 1
  fi
}

queue_require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || {
      queue_error "required command not found: $cmd"
      return 1
    }
  done
}

# --- Section 7: Array-like operations (newline-delimited) ---

queue_list_append() {
  if [ -z "$1" ]; then echo "$2"; else printf '%s\n%s\n' "$1" "$2"; fi
}

queue_list_prepend() {
  if [ -z "$2" ]; then echo "$1"; else printf '%s\n%s\n' "$1" "$2"; fi
}

queue_list_length() {
  if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}

queue_list_contains() {
  printf '%s\n' "$1" | grep -qxF "$2"
}

queue_list_remove() {
  printf '%s\n' "$1" | grep -vxF "$2"
}

queue_list_first() {
  printf '%s\n' "$1" | head -1
}

queue_list_last() {
  printf '%s\n' "$1" | tail -1
}

queue_list_nth() {
  printf '%s\n' "$1" | sed -n "${2}p"
}

queue_list_reverse() {
  printf '%s\n' "$1" | tail -r 2>/dev/null || printf '%s\n' "$1" | tac 2>/dev/null || printf '%s\n' "$1" | awk '{a[NR]=$0} END{for(i=NR;i>0;i--)print a[i]}'
}

queue_list_sort() {
  printf '%s\n' "$1" | sort
}

queue_list_uniq() {
  printf '%s\n' "$1" | sort -u
}

queue_list_filter() {
  printf '%s\n' "$1" | grep "$2" 2>/dev/null || true
}

queue_list_map_upper() {
  printf '%s\n' "$1" | tr 'a-z' 'A-Z'
}

queue_list_map_lower() {
  printf '%s\n' "$1" | tr 'A-Z' 'a-z'
}

# --- Section 8: Configuration ---

queue_config_get() {
  file="$1"; key="$2"
  grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2-
}

queue_config_set() {
  file="$1"; key="$2"; val="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$file" && rm -f "${file}.bak"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

queue_config_has() {
  grep -q "^${1}=" "$2" 2>/dev/null
}

queue_config_keys() {
  grep -v '^#' "$1" 2>/dev/null | grep -v '^$' | cut -d= -f1
}

queue_config_dump() {
  printf '--- config: %s ---\n' "$1"
  grep -v '^#' "$1" 2>/dev/null | grep -v '^$' | sort
  printf '--- end ---\n'
}

# --- Section 9: Error handling ---

queue_die() {
  queue_error "$@"
  exit 1
}

queue_trap_cleanup() {
  queue_debug "cleanup triggered"
  [ -n "${QUEUE_TMPDIR:-}" ] && rm -rf "$QUEUE_TMPDIR"
}

queue_setup_trap() {
  trap queue_trap_cleanup EXIT INT TERM
}

queue_retry() {
  max="$1"; shift
  attempt=0
  while [ $attempt -lt "$max" ]; do
    if "$@" 2>/dev/null; then return 0; fi
    attempt=$((attempt + 1))
    queue_warn "retry $attempt/$max: $*"
    sleep 1
  done
  return 1
}

# --- Section 10: Task core functions (THE ACTUAL DOMAIN) ---

# task_make_id <name> — stable task ID from a name.
# Must be idempotent: task_make_id(task_make_id(x)) == task_make_id(x).
task_make_id() {
  printf '%s\n' "$1" | tr 'A-Z_ ' 'a-z--'
}

# task_priority_label <number> — human label for priority 1-10.
task_priority_label() {
  p="$1"
  if [ "$p" -le 2 ] 2>/dev/null; then echo "critical"
  elif [ "$p" -le 4 ] 2>/dev/null; then echo "high"
  elif [ "$p" -le 6 ] 2>/dev/null; then echo "medium"
  elif [ "$p" -le 8 ] 2>/dev/null; then echo "low"
  else echo "minimal"
  fi
}

# task_status_valid <status> — rc 0 if status is a known value.
task_status_valid() {
  case "$1" in
    pending|running|done|failed|cancelled) return 0 ;;
    *) return 1 ;;
  esac
}

# task_create <name> <priority> — print a task record line.
# Format: id|name|priority|status|created
task_create() {
  name="$1"
  pri="${2:-$QUEUE_DEFAULT_PRIORITY}"
  id="$(task_make_id "$name")"
  printf '%s|%s|%s|pending|%s\n' "$id" "$name" "$pri" "$(queue_epoch)"
}

# task_parse_field <record> <field_number> — extract field from pipe-delimited record.
task_parse_field() {
  printf '%s\n' "$1" | cut -d'|' -f"$2"
}

# task_get_id <record>
task_get_id() { task_parse_field "$1" 1; }

# task_get_name <record>
task_get_name() { task_parse_field "$1" 2; }

# task_get_priority <record>
task_get_priority() { task_parse_field "$1" 3; }

# task_get_status <record>
task_get_status() { task_parse_field "$1" 4; }

# task_set_status <record> <new_status> — return updated record.
task_set_status() {
  rec="$1"; new_status="$2"
  id="$(task_get_id "$rec")"
  pri="$(task_get_priority "$rec")"
  created="$(task_parse_field "$rec" 5)"
  printf '%s|%s|%s|%s\n' "$id" "$pri" "$new_status" "$created"
}

# task_format <record> — human-readable single line.
task_format() {
  id="$(task_get_id "$1")"
  name="$(task_get_name "$1")"
  pri="$(task_get_priority "$1")"
  status="$(task_get_status "$1")"
  label="$(task_priority_label "$pri")"
  printf '[%s] %s (%s, %s)\n' "$id" "$name" "$status" "$label"
}

# --- Section 11: Dependency graph ---

# dep_add <deps_var> <from_id> <to_id> — append a dependency edge.
dep_add() {
  printf '%s -> %s\n' "$2" "$3"
}

# dep_has <deps> <from_id> <to_id> — rc 0 if edge exists.
dep_has() {
  printf '%s\n' "$1" | grep -qxF "$2 -> $3"
}

# dep_list_deps <deps> <id> — list direct dependencies of id.
dep_list_deps() {
  printf '%s\n' "$1" | grep "^$2 -> " | sed 's/.* -> //'
}

# dep_list_rdeps <deps> <id> — list reverse dependencies (who depends on id).
dep_list_rdeps() {
  printf '%s\n' "$1" | grep " -> $2$" | sed 's/ -> .*//'
}

# dep_is_satisfied <deps> <id> <done_list> — rc 0 if all deps of id are in done_list.
dep_is_satisfied() {
  deps_of="$(dep_list_deps "$1" "$2")"
  if [ -z "$deps_of" ]; then return 0; fi
  while IFS= read -r dep; do
    queue_list_contains "$3" "$dep" || return 1
  done <<EOF
$deps_of
EOF
  return 0
}

# dep_topo_sort <deps> <all_ids> — topological sort, print in execution order.
dep_topo_sort() {
  deps="$1"; all="$2"
  done_list=""
  remaining="$all"
  max_iter=$(queue_list_length "$all")
  iter=0
  while [ -n "$remaining" ] && [ $iter -le "$max_iter" ]; do
    progress=0
    next_remaining=""
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      if dep_is_satisfied "$deps" "$id" "$done_list"; then
        echo "$id"
        done_list="$(queue_list_append "$done_list" "$id")"
        progress=1
      else
        next_remaining="$(queue_list_append "$next_remaining" "$id")"
      fi
    done <<EOF
$remaining
EOF
    remaining="$next_remaining"
    iter=$((iter + 1))
    [ $progress -eq 0 ] && { queue_error "cycle detected in dependency graph"; return 1; }
  done
}

# --- Section 12: Queue management ---

# queue_new — initialize empty queue state.
queue_new() {
  QUEUE_TASKS=""
  QUEUE_DEPS=""
  QUEUE_COUNT=0
}

# queue_add <name> [priority] — add a task to the queue.
queue_add() {
  rec="$(task_create "$1" "${2:-}")"
  QUEUE_TASKS="$(queue_list_append "$QUEUE_TASKS" "$rec")"
  QUEUE_COUNT=$((QUEUE_COUNT + 1))
}

# queue_add_dep <from_name> <to_name> — from depends on to.
queue_add_dep() {
  from_id="$(task_make_id "$1")"
  to_id="$(task_make_id "$2")"
  edge="$(dep_add "" "$from_id" "$to_id")"
  QUEUE_DEPS="$(queue_list_append "$QUEUE_DEPS" "$edge")"
}

# queue_find <name> — print matching task record, rc 1 if not found.
queue_find() {
  id="$(task_make_id "$1")"
  printf '%s\n' "$QUEUE_TASKS" | while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    rec_id="$(task_get_id "$rec")"
    if [ "$rec_id" = "$id" ]; then
      printf '%s\n' "$rec"
      return 0
    fi
  done
  return 1
}

# queue_update_status <name> <status> — update task status in queue.
queue_update_status() {
  id="$(task_make_id "$1")"
  new_tasks=""
  printf '%s\n' "$QUEUE_TASKS" | while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    rec_id="$(task_get_id "$rec")"
    if [ "$rec_id" = "$id" ]; then
      rec="$(task_set_status "$rec" "$2")"
    fi
    new_tasks="$(queue_list_append "$new_tasks" "$rec")"
    printf '%s\n' "$new_tasks"
  done | tail -1
}

# queue_execution_order — print task ids in dependency-safe order.
queue_execution_order() {
  ids=""
  printf '%s\n' "$QUEUE_TASKS" | while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    id="$(task_get_id "$rec")"
    ids="$(queue_list_append "$ids" "$id")"
    printf '%s\n' "$ids"
  done | tail -1 | {
    read -r all_ids
    dep_topo_sort "$QUEUE_DEPS" "$all_ids"
  }
}

# queue_summary — print queue summary report.
queue_summary() {
  total=$(queue_list_length "$QUEUE_TASKS")
  pending=0; running=0; done_c=0; failed=0
  printf '%s\n' "$QUEUE_TASKS" | while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    st="$(task_get_status "$rec")"
    case "$st" in
      pending) pending=$((pending+1)) ;;
      running) running=$((running+1)) ;;
      done) done_c=$((done_c+1)) ;;
      failed) failed=$((failed+1)) ;;
    esac
    printf 'total=%d pending=%d running=%d done=%d failed=%d\n' \
      "$total" "$pending" "$running" "$done_c" "$failed"
  done | tail -1
}

# --- Section 13: Report formatting ---

queue_report_header() {
  printf '%-20s %-30s %-10s %-10s\n' "ID" "NAME" "PRIORITY" "STATUS"
  printf '%s\n' "$(queue_repeat '-' 74)"
}

queue_report_row() {
  id="$(task_get_id "$1")"
  name="$(task_get_name "$1")"
  pri="$(task_priority_label "$(task_get_priority "$1")")"
  st="$(task_get_status "$1")"
  printf '%-20s %-30s %-10s %-10s\n' "$id" "$name" "$pri" "$st"
}

queue_report() {
  queue_report_header
  printf '%s\n' "$QUEUE_TASKS" | while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    queue_report_row "$rec"
  done
}

# --- Section 14: Serialization ---

queue_save() {
  file="$1"
  printf '%s\n' "$QUEUE_TASKS" > "$file"
  printf '%s\n' "$QUEUE_DEPS" > "${file%.dat}.deps"
}

queue_load() {
  file="$1"
  QUEUE_TASKS="$(cat "$file" 2>/dev/null)"
  QUEUE_DEPS="$(cat "${file%.dat}.deps" 2>/dev/null)"
  QUEUE_COUNT=$(queue_list_length "$QUEUE_TASKS")
}
