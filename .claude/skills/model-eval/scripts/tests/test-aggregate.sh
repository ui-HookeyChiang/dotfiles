#!/bin/sh
# aggregate.py: dedupes reruns (last wins), computes pass and cost/pass.
set -eu
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
cat > "$D/ledger.jsonl" << 'JSON'
{"q":"executor-v1","model":"m1","run":"1","pass":false,"cost_usd":0.10,"out_tok":100,"latency_ms":1000}
{"q":"executor-v1","model":"m1","run":"1","pass":true,"cost_usd":0.20,"out_tok":100,"latency_ms":1000}
{"q":"executor-v1","model":"m1","run":"2","pass":true,"cost_usd":0.30,"out_tok":100,"latency_ms":1000}
{"q":"scanner","model":"m1","run":"1","accuracy":0.5,"cost_usd":0.01,"out_tok":10,"latency_ms":500}
JSON
OUT=$(python3 "$(dirname "$0")/../aggregate.py" "$D/ledger.jsonl")
echo "$OUT" | grep -q 'executor-v1 m1: n=2 pass=2/2 cost/pass=\$0.250' || { echo "FAIL dedupe/pass: $OUT"; exit 1; }
echo "$OUT" | grep -q 'scanner m1: n=1.*acc=0.50' || { echo "FAIL scanner: $OUT"; exit 1; }
echo "PASS test-aggregate"
