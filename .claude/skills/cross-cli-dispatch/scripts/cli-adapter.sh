#!/usr/bin/env bash
# cli-adapter.sh — one interface, four headless CLI backends.
#
# Subcommands:
#   run          --backend <claude|cursor|codex|opencode> --model <id>
#                [--effort low|medium|high|none] [--prompt <text>|--prompt-file <f>|-]
#                [--cwd <dir>] [--max-turns <n>] [--run-dir <dir>] [--tier <t>]
#                Executes one headless run; prints ONE normalized JSON line
#                (ledger schema) to stdout. Exit: 0 ok, 75 quota_exhausted
#                (channel marked in state, caller falls down the chain),
#                1 other failure.
#   next-channel --tier <t> [--bindings <tsv>] [--state-dir <d>]
#                [--allow <backend[,backend...]>]
#                Prints "backend<TAB>model<TAB>effort" for the FIRST allowed,
#                detected channel with no quota_exhausted mark today.
#                Unsupported or exhausted/filtered chain -> JSON reason, exit 3.
#                Exit 2: unknown tier.
#   detect-channels [--state-dir <d>]
#                Prints detected backends, one per line. Uses a daily cache.
#   mark-quota   --backend <b> --model <m> --effort <e> [--state-dir <d>]
#                Appends the channel to today's quota state file.
#
# Env overrides (tests stub binaries through these):
#   CLI_ADAPTER_CLAUDE_BIN CLI_ADAPTER_CURSOR_BIN
#   CLI_ADAPTER_CODEX_BIN  CLI_ADAPTER_OPENCODE_BIN
#   CLI_ADAPTER_<BACKEND>_CRED override credential probe paths in tests/local setup
#   CROSS_CLI_DISPATCH_STATE  (default ~/.local/state/cross-cli-dispatch)

set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR_DEFAULT="${CROSS_CLI_DISPATCH_STATE:-$HOME/.local/state/cross-cli-dispatch}"

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

quota_file() { echo "$1/quota-$(date +%Y%m%d)"; }

channels_file() { echo "$1/channels-$(date +%Y%m%d)"; }

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

backend_bin() {
  case "$1" in
    claude) echo "${CLI_ADAPTER_CLAUDE_BIN:-claude}";;
    cursor) echo "${CLI_ADAPTER_CURSOR_BIN:-cursor-agent}";;
    codex) echo "${CLI_ADAPTER_CODEX_BIN:-codex}";;
    opencode) echo "${CLI_ADAPTER_OPENCODE_BIN:-opencode}";;
    *) return 1;;
  esac
}

backend_cred() {
  case "$1" in
    claude) echo "${CLI_ADAPTER_CLAUDE_CRED:-$HOME/.claude.json}";;
    cursor) echo "${CLI_ADAPTER_CURSOR_CRED:-$HOME/.cursor/credentials.json}";;
    codex) echo "${CLI_ADAPTER_CODEX_CRED:-$HOME/.codex/auth.json}";;
    opencode) echo "${CLI_ADAPTER_OPENCODE_CRED:-$HOME/.config/opencode/auth.json}";;
    *) return 1;;
  esac
}

backend_in_list() {
  local backend="$1" list="$2" item
  IFS=',' read -r -a items <<< "$list"
  for item in "${items[@]}"; do
    [ "$backend" = "$item" ] && return 0
  done
  return 1
}

channel_allowed() {
  local backend="$1" allow="$2" detected="$3"
  if [ -n "$allow" ]; then
    backend_in_list "$backend" "$allow"; return $?
  fi
  printf '%s\n' "$detected" | grep -qxF "$backend"
}

cmd_detect_channels() {
  local state_dir="$STATE_DIR_DEFAULT"
  while [ $# -gt 0 ]; do case "$1" in
    --state-dir) state_dir="$2"; shift 2;;
    *) usage;;
  esac; done

  local cf backend bin cred
  cf="$(channels_file "$state_dir")"
  if [ -f "$cf" ]; then
    cat "$cf"
    return 0
  fi

  mkdir -p "$state_dir"
  : > "$cf"
  for backend in claude cursor codex opencode; do
    bin="$(backend_bin "$backend")"
    cred="$(backend_cred "$backend")"
    command -v "$bin" >/dev/null 2>&1 || continue
    case "$backend" in
      cursor)
        if [ -f "$cred" ] || "$bin" status >/dev/null 2>&1; then
          echo "$backend" >> "$cf"
        fi
        ;;
      *)
        [ -f "$cred" ] && echo "$backend" >> "$cf"
        ;;
    esac
  done
  cat "$cf"
}

cmd_mark_quota() {
  local backend="" model="" effort="" state_dir="$STATE_DIR_DEFAULT"
  while [ $# -gt 0 ]; do case "$1" in
    --backend) backend="$2"; shift 2;;
    --model) model="$2"; shift 2;;
    --effort) effort="$2"; shift 2;;
    --state-dir) state_dir="$2"; shift 2;;
    *) usage;;
  esac; done
  [ -n "$backend" ] && [ -n "$model" ] || usage
  mkdir -p "$state_dir"
  echo "$backend,$model,$effort" >> "$(quota_file "$state_dir")"
}

json_no_channel() {
  local tier="$1" reason="$2" action="$3"
  python3 - "$tier" "$reason" "$action" <<'PYJSON'
import json, sys
print(json.dumps({"tier": sys.argv[1], "reason": sys.argv[2], "action": sys.argv[3]}, separators=(",", ":")))
PYJSON
}

# Per-family effort-suffix map for cursor backend.
# Cursor model IDs are <family>-<effort_suffix>. This map translates canonical
# effort labels (low|medium|high) to the family-specific suffix cursor expects.
# Families not listed here use the canonical label as-is (identity mapping).
CURSOR_EFFORT_MAP="${CURSOR_EFFORT_MAP:-$SKILL_DIR/data/cursor-effort-map.tsv}"

cursor_effort_suffix() {
  local model="$1" effort="$2"
  # If a map file exists and has a row for this model+effort, use it
  if [ -f "$CURSOR_EFFORT_MAP" ]; then
    local suffix
    suffix=$(awk -F'\t' -v m="$model" -v e="$effort" \
      '/^[^#]/ && $1==m && $2==e {print $3; exit}' "$CURSOR_EFFORT_MAP")
    if [ -n "$suffix" ]; then
      echo "$suffix"
      return
    fi
  fi
  # Default: canonical label is the suffix (identity)
  echo "$effort"
}

cmd_next_channel() {
  local tier="" bindings="$SKILL_DIR/bindings.tsv" state_dir="$STATE_DIR_DEFAULT"
  local allow="" detected=""
  while [ $# -gt 0 ]; do case "$1" in
    --tier) tier="$2"; shift 2;;
    --bindings) bindings="$2"; shift 2;;
    --state-dir) state_dir="$2"; shift 2;;
    --allow) allow="$2"; shift 2;;
    *) usage;;
  esac; done
  [ -n "$tier" ] || usage
  local chain
  chain=$(awk -F'\t' -v t="$tier" '$1==t {print $2}' "$bindings")
  [ -n "$chain" ] || { echo "unknown tier: $tier" >&2; exit 2; }

  case "$chain" in
    unsupported) json_no_channel "$tier" unsupported defer; exit 3;;
    unsupported:*) json_no_channel "$tier" unsupported "${chain#unsupported:}"; exit 3;;
  esac

  [ -n "$allow" ] || detected="$(cmd_detect_channels --state-dir "$state_dir")"

  local qf ch backend action="retry"
  qf="$(quota_file "$state_dir")"
  for ch in ${chain//;/ }; do
    backend="${ch%%,*}"
    channel_allowed "$backend" "$allow" "$detected" || continue
    if [ ! -f "$qf" ] || ! grep -qxF "$ch" "$qf"; then
      echo "$ch" | tr ',' '\t'; return 0
    fi
  done

  [ "$tier" = decide ] && action="surface_to_user"
  json_no_channel "$tier" channel_exhausted "$action"
  exit 3
}

cmd_run() {
  local backend="" model="" effort="low" prompt="" prompt_file="" cwd="$PWD"
  local max_turns=8 run_dir="" tier="adapter" state_dir="$STATE_DIR_DEFAULT"
  local run_idx=1
  while [ $# -gt 0 ]; do case "$1" in
    --backend) backend="$2"; shift 2;;
    --model) model="$2"; shift 2;;
    --effort) effort="$2"; shift 2;;
    --prompt) prompt="$2"; shift 2;;
    --prompt-file) prompt_file="$2"; shift 2;;
    --cwd) cwd="$2"; shift 2;;
    --max-turns) max_turns="$2"; shift 2;;
    --run-dir) run_dir="$2"; shift 2;;
    --tier) tier="$2"; shift 2;;
    --run-idx) run_idx="$2"; shift 2;;
    --state-dir) state_dir="$2"; shift 2;;
    -) prompt="$(cat)"; shift;;
    *) usage;;
  esac; done
  [ -n "$backend" ] && [ -n "$model" ] || usage
  [ -n "$prompt_file" ] && prompt="$(cat "$prompt_file")"
  [ -n "$prompt" ] || { echo "empty prompt" >&2; exit 1; }
  [ -n "$run_dir" ] || run_dir="$(mktemp -d "${TMPDIR:-/tmp}/cli-adapter.XXXXXX")"
  mkdir -p "$run_dir"

  # Validate canonical effort vocabulary
  case "$effort" in
    low|medium|high|none) ;;
    *) echo "invalid effort: $effort (valid: low, medium, high, none)" >&2; exit 1;;
  esac

  local bin args=()
  case "$backend" in
    claude)
      bin="${CLI_ADAPTER_CLAUDE_BIN:-claude}"
      args=(-p "$prompt" --model "$model" --output-format json --max-turns "$max_turns")
      [ "$effort" != none ] && args+=(--effort "$effort")
      ;;
    cursor)
      # Cursor effort = model-name suffix; translate canonical effort via
      # per-family map. If model already has a known suffix, skip.
      local m="$model"
      case "$m" in *-low|*-medium|*-high) ;; *)
        if [ "$effort" != none ]; then
          local cursor_suffix
          cursor_suffix="$(cursor_effort_suffix "$m" "$effort")"
          m="$m-$cursor_suffix"
        fi;; esac
      bin="${CLI_ADAPTER_CURSOR_BIN:-cursor-agent}"
      args=(-p "$prompt" --model "$m" --force --output-format json)
      ;;
    codex)
      bin="${CLI_ADAPTER_CODEX_BIN:-codex}"
      args=(exec -m "$model" --dangerously-bypass-approvals-and-sandbox --json)
      [ "$effort" != none ] && args+=(-c "model_reasoning_effort=$effort")
      args+=("$prompt")
      ;;
    opencode)
      bin="${CLI_ADAPTER_OPENCODE_BIN:-opencode}"
      args=(run -m "$model" --format json)
      [ "$effort" != none ] && args+=(--variant "$effort")
      args+=("$prompt")
      ;;
    *) echo "unknown backend: $backend" >&2; exit 1;;
  esac

  local start end rc
  start=$(now_ms)
  (cd "$cwd" && "$bin" "${args[@]}" \
    > "$run_dir/raw.out" 2> "$run_dir/stderr.log")
  rc=$?
  end=$(now_ms)

  BACKEND="$backend" MODEL="$model" EFFORT="$effort" TIER="$tier" \
  RUN_IDX="$run_idx" RUN_DIR="$run_dir" RC="$rc" LAT=$((end-start)) \
  python3 "$SKILL_DIR/scripts/normalize.py"
  local nrc=$?
  if [ "$nrc" -eq 75 ]; then
    cmd_mark_quota --backend "$backend" --model "$model" --effort "$effort" \
      --state-dir "$state_dir"
    exit 75
  fi
  exit "$nrc"
}

case "${1:-}" in
  run) shift; cmd_run "$@";;
  next-channel) shift; cmd_next_channel "$@";;
  detect-channels) shift; cmd_detect_channels "$@";;
  mark-quota) shift; cmd_mark_quota "$@";;
  *) usage;;
esac
