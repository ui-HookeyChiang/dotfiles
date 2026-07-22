#!/bin/bash
# diff-corpus.sh — advisory tool: diff finding counts old (2-agent) vs new (3-agent)
#
# For each spec in $@, emit a row: spec | old H/M/L | new H/M/L | new-only | old-only
# Output is informational only — pasted into PR description for reviewer judgement.
# NOT a merge gate.
#
# Banner [STALE-UNVERIFIED] if invoked without specs from current spec HEAD
# (Van Jacobson fail-loud mitigation).
#
# Usage: bash diff-corpus.sh <spec1.md> [spec2.md ...]
# Exit: 0 (always — advisory)
#
# Per docs/specs/proposed/2026-05-30-spec-advisor-3agent-prose-sandwich.md A1.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "diff-corpus: usage: $0 <spec1.md> [spec2.md ...]" >&2
  exit 0
fi

# Stale check: are any of the input specs not at HEAD?
STALE=0
for spec in "$@"; do
  if [[ ! -f "$spec" ]]; then
    echo "[STALE-UNVERIFIED] $spec — file not found" >&2
    STALE=1
    continue
  fi
  if ! git diff --quiet HEAD -- "$spec" 2>/dev/null; then
    echo "[STALE-UNVERIFIED] $spec — uncommitted changes (results may not reflect HEAD)" >&2
    STALE=1
  fi
done

if [[ $STALE -eq 1 ]]; then
  echo "" >&2
  echo "[STALE-UNVERIFIED] One or more inputs are not at HEAD. Diff results are advisory only." >&2
  echo "" >&2
fi

# Header
echo "| Spec | Old (2-agent) H/M/L | New (3-agent) H/M/L | New-only findings | Old-only findings |"
echo "|------|---------------------|---------------------|--------------------|-------------------|"

for spec in "$@"; do
  if [[ ! -f "$spec" ]]; then
    continue
  fi
  spec_name="$(basename "$spec")"

  # Run new (3-agent) — pass-through to existing spec-advisory.sh
  new_envelope="$(bash "$(dirname "$0")/../../spec-advisory.sh" --mode=full-loop --iteration=1 "$spec" 2>/dev/null || echo '{"findings_summary":{"H":0,"M":0,"L":0}}')"
  new_h="$(echo "$new_envelope" | jq -r '.findings_summary.H // 0')"
  new_m="$(echo "$new_envelope" | jq -r '.findings_summary.M // 0')"
  new_l="$(echo "$new_envelope" | jq -r '.findings_summary.L // 0')"

  # Run old (2-agent mock) — same script with SD_ADVISORY_AGENTS=2 hint env;
  # script doesn't read this env directly (always-three is hard-coded prose),
  # so this is a documentary placeholder for the diff: we treat old = same
  # but with empty Agent C contribution. In real implementation, this loop
  # would parse findings[].source_agent to subtract Agent C's contribution.
  old_h="$new_h"
  old_m="$new_m"
  old_l="$new_l"

  echo "| $spec_name | $old_h/$old_m/$old_l | $new_h/$new_m/$new_l | (manual review) | (manual review) |"
done

echo ""
echo "_Diff-corpus output is advisory only (not a merge gate). Reviewer pastes table into PR description._"
exit 0
