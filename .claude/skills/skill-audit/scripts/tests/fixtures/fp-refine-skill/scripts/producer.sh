#!/usr/bin/env bash
# producer.sh — emits the contract JSON on stdout.
set -euo pipefail
val="hello"
jq -nc \
  --arg paired_field "$val" \
  --arg writeonly_field "$val" \
  '{paired_field:$paired_field, writeonly_field:$writeonly_field}'
bash "$(dirname "$0")/consumer.sh"
