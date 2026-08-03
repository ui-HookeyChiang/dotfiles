#!/bin/sh
# Evidence axes: capability key carries effort/tier; backend is metadata only.
set -eu
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
S="$(cd "$(dirname "$0")/.." && pwd)"

# 1. Two effort variants of the same (q, model, run) stay distinct cells.
cat > "$D/effort.jsonl" << 'JSON'
{"q":"executor-v1","model":"m1","run":"1","effort":"low","pass":true,"cost_usd":0.10,"out_tok":100,"latency_ms":1000}
{"q":"executor-v1","model":"m1","run":"1","effort":"high","pass":false,"cost_usd":0.20,"out_tok":100,"latency_ms":1000}
JSON
OUT=$(python3 "$S/aggregate.py" "$D/effort.jsonl")
[ "$(echo "$OUT" | grep -c 'executor-v1 m1')" -eq 2 ] || { echo "FAIL effort split (want 2 cells): $OUT"; exit 1; }
echo "$OUT" | grep -q 'effort=low' || { echo "FAIL effort=low absent: $OUT"; exit 1; }
echo "$OUT" | grep -q 'effort=high' || { echo "FAIL effort=high absent: $OUT"; exit 1; }

# Same-model equivalence: backend is not a key dimension, so two backends
# reporting the same (q, model, effort, run) collapse to one cell.
cat > "$D/backend.jsonl" << 'JSON'
{"q":"executor-v1","model":"m1","run":"1","effort":"low","backend":"claude","pass":true,"cost_usd":0.10,"out_tok":100,"latency_ms":1000}
{"q":"executor-v1","model":"m1","run":"1","effort":"low","backend":"codex","pass":true,"cost_usd":0.10,"out_tok":100,"latency_ms":1000}
JSON
OUT=$(python3 "$S/aggregate.py" "$D/backend.jsonl")
[ "$(echo "$OUT" | grep -c 'executor-v1 m1')" -eq 1 ] || { echo "FAIL backend must not split cells: $OUT"; exit 1; }

# Tier shown when present, and separates otherwise-identical cells.
cat > "$D/tier.jsonl" << 'JSON'
{"q":"executor-v1","model":"m1","run":"1","effort":"low","tier":"scan","pass":true,"cost_usd":0.10,"out_tok":100,"latency_ms":1000}
{"q":"executor-v1","model":"m1","run":"1","effort":"low","tier":"execute","pass":true,"cost_usd":0.10,"out_tok":100,"latency_ms":1000}
JSON
OUT=$(python3 "$S/aggregate.py" "$D/tier.jsonl")
[ "$(echo "$OUT" | grep -c 'executor-v1 m1')" -eq 2 ] || { echo "FAIL tier split: $OUT"; exit 1; }
echo "$OUT" | grep -q 'tier=scan' || { echo "FAIL tier=scan absent: $OUT"; exit 1; }

# 2. Legacy rows (no effort/tier/backend) aggregate unchanged: read-time defaults.
cat > "$D/legacy.jsonl" << 'JSON'
{"q":"executor-v1","model":"m1","run":"1","pass":false,"cost_usd":0.10,"out_tok":100,"latency_ms":1000}
{"q":"executor-v1","model":"m1","run":"1","pass":true,"cost_usd":0.20,"out_tok":100,"latency_ms":1000}
{"q":"executor-v1","model":"m1","run":"2","pass":true,"cost_usd":0.30,"out_tok":100,"latency_ms":1000}
{"q":"scanner","model":"m1","run":"1","accuracy":0.5,"cost_usd":0.01,"out_tok":10,"latency_ms":500}
JSON
OUT=$(python3 "$S/aggregate.py" "$D/legacy.jsonl")
[ "$(echo "$OUT" | grep -c .)" -eq 2 ] || { echo "FAIL legacy row count (want 2): $OUT"; exit 1; }
echo "$OUT" | grep -q 'executor-v1 m1: n=2 pass=2/2 cost/pass=\$0.250' || { echo "FAIL legacy dedupe: $OUT"; exit 1; }
echo "$OUT" | grep -q 'scanner m1: n=1.*acc=0.50' || { echo "FAIL legacy scanner: $OUT"; exit 1; }
# Absent effort/tier must not print as empty decoration.
echo "$OUT" | grep -q 'effort=' && { echo "FAIL legacy shows effort=: $OUT"; exit 1; }
echo "$OUT" | grep -q 'tier=' && { echo "FAIL legacy shows tier=: $OUT"; exit 1; }

# Mixed legacy + new rows coexist: legacy is its own effort-unknown cell.
cat > "$D/mixed.jsonl" << 'JSON'
{"q":"executor-v1","model":"m1","run":"1","pass":true,"cost_usd":0.10,"out_tok":100,"latency_ms":1000}
{"q":"executor-v1","model":"m1","run":"1","effort":"high","pass":true,"cost_usd":0.20,"out_tok":100,"latency_ms":1000}
JSON
OUT=$(python3 "$S/aggregate.py" "$D/mixed.jsonl")
[ "$(echo "$OUT" | grep -c 'executor-v1 m1')" -eq 2 ] || { echo "FAIL mixed legacy/new split: $OUT"; exit 1; }

# 3. append-ledger.py: backend from MODEL_EVAL_CLI (default claude); tier omitted when TIER unset.
mkdir -p "$D/out" "$D/run"
echo '{}' > "$D/run/claude.json"
env -u TIER -u MODEL_EVAL_CLI RUN="$D/run" OUT="$D/out" Q=q1 MODEL=m1 IDX=1 LAT=100 \
  python3 "$S/append-ledger.py"
REC=$(tail -n 1 "$D/out/ledger.jsonl")
echo "$REC" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["backend"]=="claude", r; assert "tier" not in r, r' \
  || { echo "FAIL default backend/tier-absent: $REC"; exit 1; }

env TIER=execute MODEL_EVAL_CLI=codex RUN="$D/run" OUT="$D/out" Q=q1 MODEL=m1 IDX=2 LAT=100 \
  python3 "$S/append-ledger.py"
REC=$(tail -n 1 "$D/out/ledger.jsonl")
echo "$REC" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["backend"]=="codex", r; assert r["tier"]=="execute", r' \
  || { echo "FAIL backend/tier from env: $REC"; exit 1; }

# 4. append-harness.py: valid jsonl row, repeated runs append.
env MODEL_EVAL_CLI=codex OUT="$D/out" MODEL=m1 RC=0 LAT=250 python3 "$S/append-harness.py"
env MODEL_EVAL_CLI=codex OUT="$D/out" MODEL=m1 RC=1 LAT=90 python3 "$S/append-harness.py"
[ "$(grep -c . "$D/out/harness.jsonl")" -eq 2 ] || { echo "FAIL harness append"; exit 1; }
python3 - "$D/out/harness.jsonl" << 'PY' || { echo "FAIL harness record shape"; exit 1; }
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert [r["backend"] for r in rows] == ["codex", "codex"], rows
assert [r["model"] for r in rows] == ["m1", "m1"], rows
assert [r["rc"] for r in rows] == [0, 1], rows
assert [r["latency_ms"] for r in rows] == [250, 90], rows
assert [r["ok"] for r in rows] == [True, False], rows
PY

# Harness backend defaults to claude, matching append-ledger.
env -u MODEL_EVAL_CLI OUT="$D/out" MODEL=m2 RC=0 LAT=10 python3 "$S/append-harness.py"
tail -n 1 "$D/out/harness.jsonl" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["backend"]=="claude", r' \
  || { echo "FAIL harness default backend"; exit 1; }

# Capability ledger never grows a backend key dimension: harness rows stay out of it.
[ "$(grep -c . "$D/out/ledger.jsonl")" -eq 2 ] || { echo "FAIL harness leaked into ledger"; exit 1; }

echo "PASS test-evidence-axes"
