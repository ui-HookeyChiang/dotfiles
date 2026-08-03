#!/usr/bin/env bash
# backfill-incumbent-baselines.sh — re-run Anthropic incumbent baselines into durable ledger.
# Usage: nohup bash ~/.claude/skill-dev/model-eval/scripts/backfill-incumbent-baselines.sh > ~/model-eval-backfill.log 2>&1 &
set -euo pipefail

export MODEL_EVAL_OUT=~/model-eval-out-cross-cli
SD="$(cd "$(dirname "$0")" && pwd)"

echo "=== BACKFILL START $(date) ==="

for i in 1 2 3; do
  echo "--- haiku-4-5 scanner run $i ---"
  sh "$SD/run-scanner.sh" claude-haiku-4-5 "$i" low

  echo "--- haiku-4-5 executor-v3 run $i ---"
  sh "$SD/run-executor.sh" claude-haiku-4-5 "$i" v3 low

  echo "--- sonnet-5 review run $i ---"
  sh "$SD/run-review.sh" claude-sonnet-5 "$i" low

  echo "--- sonnet-5 search run $i ---"
  sh "$SD/run-search.sh" claude-sonnet-5 "$i" low

  echo "--- sonnet-5 deep-v2 run $i ---"
  sh "$SD/run-deep.sh" claude-sonnet-5 "$i" low v2
done

for i in 2 3; do
  echo "--- opus-4-6 deep-v2 run $i ---"
  sh "$SD/run-deep.sh" claude-opus-4-6 "$i" low v2
done

echo "=== BACKFILL DONE $(date) ==="
