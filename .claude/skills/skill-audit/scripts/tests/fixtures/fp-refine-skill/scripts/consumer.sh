#!/usr/bin/env bash
# consumer.sh — reads the paired contract field.
set -euo pipefail
json=$(bash "$(dirname "$0")/producer.sh")
branch=$(echo "$json" | jq -r '.paired_field')
echo "got: $branch"
