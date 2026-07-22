#!/bin/bash
# tests/step-1.5-noop/test.sh — Step 1.5 no-op baseline regression test.
# Captures deterministic structural invariants of the current Phase 1
# "no source_plan" path (no Step 1.5 in PR1, no parser invocation in
# SKILL.md). PR4's CI diffs against baseline.snapshot — any drift fails.
# See spec §Architecture "no-op contract".

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
SKILL_MD="$ROOT/flow-dev/SKILL.md"
PARSER="$ROOT/flow-dev/scripts/adopt-superpowers-plan.sh"
BASELINE="$HERE/baseline.snapshot"

# Count occurrences of a fixed-string pattern in a file. Returns 0 on
# no match (without triggering set -e); always emits a single integer.
count_matches() {
  local pattern=$1 file=$2 n
  n="$(grep -c -F -- "$pattern" "$file" 2>/dev/null || true)"
  # grep -c on no-match prints "0" and exits 1; the `|| true` swallows
  # the exit but we still want to coerce empty / multi-line output.
  n="${n//[^0-9]/}"
  printf '%s' "${n:-0}"
}

snapshot() {
  # 1. Phase 1 step markers (count occurrences of "Step 1.N" headings).
  local marker count
  for marker in "Step 1.1" "Step 1.2" "Step 1.3" "Step 1.4" "Step 1.5"; do
    count="$(count_matches "**$marker**" "$SKILL_MD")"
    printf 'phase1_marker[%s]=%s\n' "$marker" "$count"
  done

  # 2. adopt-superpowers-plan.sh invocation reference in SKILL.md
  # (must be absent in PR1, present in PR3+).
  printf 'skill_md_invokes_parser=%s\n' \
    "$(count_matches "adopt-superpowers-plan.sh" "$SKILL_MD")"

  # 3. source_plan frontmatter reference in SKILL.md
  # (absent in PR1+PR2, present in PR3 narrative).
  printf 'skill_md_references_source_plan=%s\n' \
    "$(count_matches "source_plan" "$SKILL_MD")"

  # 4. Parser script exists on disk (PR1+: yes).
  if [[ -x "$PARSER" ]] || [[ -r "$PARSER" ]]; then
    printf 'parser_script_exists=1\n'
  else
    printf 'parser_script_exists=0\n'
  fi
}

if [[ "${1:-}" == "--capture" ]]; then
  # One-shot mode for regenerating the baseline. Not used by CI.
  snapshot > "$BASELINE"
  echo "wrote baseline to $BASELINE" >&2
  exit 0
fi

ACTUAL="$(snapshot)"

if [[ ! -f "$BASELINE" ]]; then
  echo "step-1.5-noop: missing baseline at $BASELINE" >&2
  echo "$ACTUAL"
  exit 1
fi

if diff -u "$BASELINE" <(printf '%s\n' "$ACTUAL") >/dev/null; then
  echo "PASS: Step 1.5 no-op baseline matches"
  exit 0
else
  echo "FAIL: Step 1.5 no-op baseline drift:"
  diff -u "$BASELINE" <(printf '%s\n' "$ACTUAL") | sed 's/^/  /'
  exit 1
fi
