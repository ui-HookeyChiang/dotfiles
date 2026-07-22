#!/usr/bin/env bash
# integration/adopt-superpowers-plan-e2e/test.sh — Phase 3 cross-task
# integration suite for flow-dev-adopt-superpowers-plan.
#
# Verifies the contract surface of the adopt-superpowers-plan parser:
#   PR1: flow-dev/scripts/adopt-superpowers-plan.sh (JSON v2 parser)
#   PR3: flow-dev/SKILL.md Step 1.5 narrative (no-op contract)
#   PR4: drift-check CI + baseline (covered by step-1.5-noop regression)
#
# Flows:
#   2. cross-session resume — manual source_plan -> parser JSON v2 schema
#   3. no-plan regression (delegates to step-1.5-noop)
#   5. plan_mtime emission (parser lacks stale-warning; demoted from §spec)
#
# Self-contained: builds tmpdir fixtures, asserts, cleans up.
# Permanent regression suite per flow-dev SKILL.md Phase 3.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../../.." && pwd)"
FIXTURES="$HERE/fixtures"

PARSER="$ROOT/flow-dev/scripts/adopt-superpowers-plan.sh"
STEP15_NOOP="$ROOT/flow-dev/scripts/tests/step-1.5-noop/test.sh"

PASS=0
FAIL=0
declare -a RESULTS=()

pass() {
    PASS=$((PASS + 1))
    RESULTS+=("PASS  $1")
    echo "  PASS  $1"
}
fail() {
    FAIL=$((FAIL + 1))
    RESULTS+=("FAIL  $1: $2")
    echo "  FAIL  $1: $2"
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "FATAL: missing tool: $1" >&2
        exit 2
    fi
}

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "FATAL: required file not found: $1" >&2
        exit 2
    fi
}

require_tool python3
require_tool jq
require_file "$PARSER"
require_file "$STEP15_NOOP"

# ---------------------------------------------------------------------------
# Flow 2: cross-session resume — manual source_plan + parser JSON v2 schema
# ---------------------------------------------------------------------------
flow2() {
    echo ""
    echo "Flow 2: cross-session resume — parser emits JSON v2 schema"

    local tmp plan json missing
    tmp="$(mktemp -d -t e2e-flow2-XXXXXX)"
    trap 'rm -rf "$tmp"' RETURN

    mkdir -p "$tmp/docs/specs/proposed" "$tmp/docs/superpowers/plans"
    plan="$tmp/docs/superpowers/plans/2099-06-01-foo.md"
    cp "$FIXTURES/2099-06-01-foo.md" "$plan"

    # Spec in proposed/ with manually set source_plan (simulates a resumed
    # session: spec already promoted, frontmatter wins per SKILL.md Step 1.5).
    cat >"$tmp/docs/specs/proposed/2099-06-01-foo.md" <<'SPEC_EOF'
---
title: "foo"
kind: spec
status: proposed
source_plan: docs/superpowers/plans/2099-06-01-foo.md
---

# Foo

Resumed cross-session.
SPEC_EOF

    # Frontmatter path must resolve relative to the repo root (PR3 contract).
    if [[ ! -f "$tmp/$(grep '^source_plan:' \
            "$tmp/docs/specs/proposed/2099-06-01-foo.md" \
            | awk '{print $2}')" ]]; then
        fail "flow2" "source_plan path does not resolve under repo root"
        return
    fi

    set +e
    json="$(bash "$PARSER" "$plan" 2>/dev/null)"
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
        fail "flow2" "parser exit $rc on valid plan"
        return
    fi

    # JSON v2 schema (per spec §Architecture + PR1 source):
    #   schema_version (2), plan_path, plan_mtime, tasks[],
    #   suggested_merge_groups[], warnings[], parallel_layers
    # (v1 only had schema_version=1 with no parallel_layers; Task 1 bumped
    # the version when adding the parallel_layers field.)
    missing=""
    for key in schema_version plan_path plan_mtime tasks \
                suggested_merge_groups warnings; do
        if ! printf '%s' "$json" | jq -e --arg k "$key" \
                'has($k)' >/dev/null 2>&1; then
            missing="$missing $key"
        fi
    done
    if [[ -n "$missing" ]]; then
        fail "flow2" "missing schema keys:$missing"
        return
    fi

    local schema_v task_count
    schema_v="$(printf '%s' "$json" | jq -r '.schema_version')"
    task_count="$(printf '%s' "$json" | jq -r '.tasks | length')"
    if [[ "$schema_v" != "2" ]]; then
        fail "flow2" "schema_version=$schema_v, expected 2"
        return
    fi
    if [[ "$task_count" != "2" ]]; then
        fail "flow2" "tasks length=$task_count, expected 2 (fixture)"
        return
    fi

    # Per-task contract: each task has index/title/files_*/test_commands/
    # commit_hint/estimated_lines (SKILL.md Step 1.5 consumes these).
    local task_keys
    task_keys="$(printf '%s' "$json" \
        | jq -r '.tasks[0] | keys_unsorted | join(",")')"
    for k in index title files_create files_modify files_test \
              test_commands commit_hint estimated_lines; do
        if [[ ",$task_keys," != *",$k,"* ]]; then
            fail "flow2" "tasks[0] missing key '$k'"
            return
        fi
    done

    pass "flow2: parser emitted JSON v2 with all schema keys"
}

# ---------------------------------------------------------------------------
# Flow 3: no-plan regression — delegate to step-1.5-noop baseline
# ---------------------------------------------------------------------------
flow3() {
    echo ""
    echo "Flow 3: no-plan no-op regression (delegates to step-1.5-noop)"

    set +e
    bash "$STEP15_NOOP" >/dev/null 2>&1
    local rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        pass "flow3: step-1.5-noop baseline matches"
    else
        fail "flow3" "step-1.5-noop test.sh exited $rc (CRITICAL — investigate)"
    fi
}

# ---------------------------------------------------------------------------
# Flow 5: plan_mtime emission with stale timestamp
# (parser lacks stale-warning logic — verified via rg on PR1 source —
#  so this flow asserts plan_mtime is emitted as ISO-8601 UTC instead.)
# ---------------------------------------------------------------------------
flow5() {
    echo ""
    echo "Flow 5: plan_mtime emitted for stale plan"

    local tmp plan json mtime
    tmp="$(mktemp -d -t e2e-flow5-XXXXXX)"
    trap 'rm -rf "$tmp"' RETURN

    plan="$tmp/2099-06-01-stale.md"
    cp "$FIXTURES/2099-06-01-stale.md" "$plan"
    # Stale: mtime in the past (Jan 1, 2020).
    touch -d "2020-01-01T00:00:00Z" "$plan"

    set +e
    json="$(bash "$PARSER" "$plan" 2>/dev/null)"
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
        fail "flow5" "parser exit $rc on stale plan"
        return
    fi

    mtime="$(printf '%s' "$json" | jq -r '.plan_mtime')"
    if [[ -z "$mtime" || "$mtime" == "null" ]]; then
        fail "flow5" "plan_mtime missing/null in parser JSON"
        return
    fi
    # Expect ISO-8601 UTC (per parser strftime "%Y-%m-%dT%H:%M:%SZ"),
    # and the year must be 2020 since we forced the mtime there.
    if [[ ! "$mtime" =~ ^2020-01-01T[0-9:]+Z$ ]]; then
        fail "flow5" "plan_mtime=$mtime does not match 2020-01-01T...Z"
        return
    fi
    pass "flow5: parser emitted plan_mtime=$mtime (stale-plan signal)"
}

# ---------------------------------------------------------------------------
# Run surviving flows + summary.
# ---------------------------------------------------------------------------
echo "Phase 3 integration: adopt-superpowers-plan e2e (3 flows)"
flow2
flow3
flow5

echo ""
echo "--------------------------------------------------------------"
echo "Summary:"
for line in "${RESULTS[@]}"; do
    echo "  $line"
done
echo ""
echo "  $PASS/$((PASS + FAIL)) PASS"
echo "--------------------------------------------------------------"

if (( FAIL == 0 )); then
    exit 0
fi
exit 1
