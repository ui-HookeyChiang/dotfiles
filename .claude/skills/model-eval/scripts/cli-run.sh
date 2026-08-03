#!/bin/sh
# usage: cli-run.sh <model> <effort> <max_turns> <out_json_path>
# Reads prompt on stdin. Writes claude.json-compatible object to out_json_path.
# MODEL_EVAL_CLI: explicit backend override. When unset, auto-resolves from
#                 cross-cli-dispatch/inventory.tsv (model→backend lookup).
#                 Falls back to "claude" if model not in inventory.
# MODEL_EVAL_CLAUDE_BIN: override claude binary (for testing).
# Exit: 0 ok, 75 quota_exhausted, 1 other failure.
set -u
MODEL="$1"; EFFORT="$2"; MAX_TURNS="$3"; OUT_JSON="$4"
PROMPT="$(cat)"
CLAUDE_BIN="${MODEL_EVAL_CLAUDE_BIN:-claude}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ADAPTER="$REPO_ROOT/cross-cli-dispatch/scripts/cli-adapter.sh"
INVENTORY="$REPO_ROOT/cross-cli-dispatch/inventory.tsv"

# Auto-resolve backend from inventory.tsv when MODEL_EVAL_CLI is unset
if [ -n "${MODEL_EVAL_CLI:-}" ]; then
  BACKEND="$MODEL_EVAL_CLI"
elif [ -f "$INVENTORY" ]; then
  BACKEND=$(awk -F'\t' -v m="$MODEL" '/^[^#]/ && $2==m {print $1; exit}' "$INVENTORY")
  BACKEND="${BACKEND:-claude}"
else
  BACKEND="claude"
fi

if [ "$BACKEND" = "claude" ]; then
  EXTRA_FLAGS=""
  [ "${MODEL_EVAL_CLAUDE_SKIP_PERMISSIONS:-}" = "1" ] && EXTRA_FLAGS="--dangerously-skip-permissions"
  # shellcheck disable=SC2086
  "$CLAUDE_BIN" -p "$PROMPT" --model "$MODEL" --effort "$EFFORT" \
    --output-format json --max-turns "$MAX_TURNS" $EXTRA_FLAGS > "$OUT_JSON" 2>/dev/null
  exit $?
fi

# Non-claude backend: route through cli-adapter.sh
ADAPTER_OUT=$(printf '%s' "$PROMPT" | bash "$ADAPTER" run \
  --backend "$BACKEND" --model "$MODEL" --effort "$EFFORT" \
  --max-turns "$MAX_TURNS" - 2>/dev/null)
ADAPTER_RC=$?

# Convert ledger JSON line to claude.json-compatible object
python3 -c "
import json, sys
a_out = sys.argv[1]
out_path = sys.argv[2]
rc = int(sys.argv[3])

try:
    a = json.loads(a_out) if a_out.strip() else {}
except Exception:
    a = {}

obj = {}
if a.get('result') is not None:
    obj['result'] = a['result']
if a.get('num_turns') is not None:
    obj['num_turns'] = a['num_turns']
if a.get('cost_usd') is not None:
    obj['total_cost_usd'] = a['cost_usd']
if a.get('api_ms') is not None:
    obj['duration_api_ms'] = a['api_ms']

usage = {}
if a.get('in_tok') is not None:
    usage['input_tokens'] = a['in_tok']
if a.get('out_tok') is not None:
    usage['output_tokens'] = a['out_tok']
if a.get('cache_create') is not None:
    usage['cache_creation_input_tokens'] = a['cache_create']
if a.get('cache_read') is not None:
    usage['cache_read_input_tokens'] = a['cache_read']
if usage:
    obj['usage'] = usage

open(out_path, 'w').write(json.dumps(obj))
" "$ADAPTER_OUT" "$OUT_JSON" "$ADAPTER_RC"
PY_RC=$?

[ "$PY_RC" -ne 0 ] && exit 1
exit "$ADAPTER_RC"
