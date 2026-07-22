#!/usr/bin/env bash
# integration/test.sh — Phase 3 end-to-end integration for Sprint 1
# (router.sh + SKILL.md Pre-flight guide).
#
# Exercises the full chain: feature description → router.sh → JSON →
# schema validation. Verifies SKILL.md Pre-flight section actually points
# at a runnable script.
#
# v3: the `shape` field and its classify-task.sh classifier were removed
# (both shapes ran all phases — nothing branched on it). The SD_SHAPE
# round-trip and classifier-probe rows are gone; schema is now 9 keys.
#
# Usage: bash flow-dev/scripts/tests/integration/test.sh
# (run from repo root)

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
ROUTER="$REPO_ROOT/flow-dev/scripts/router.sh"
SKILLMD="$REPO_ROOT/flow-dev/SKILL.md"
EVAL="$REPO_ROOT/flow-dev/evals/router-tests.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $1: $2"; }

echo "Phase 3 integration: flow-dev-router-sprint1"
echo ""

# ---------------------------------------------------------------------------
# F: router emits the v3 9-key schema with shape ABSENT.
# ---------------------------------------------------------------------------
echo "F: router v3 schema (shape removed)"
F_OUT=$(bash "$ROUTER" "irrelevant input" 2>/dev/null)
F_HAS_SHAPE=$(echo "$F_OUT" | jq -r 'has("shape")')
[[ "$F_HAS_SHAPE" == "false" ]] && pass "F.1 shape key ABSENT (v3)" \
    || fail "F.1" "shape key present: $(echo "$F_OUT" | jq -c .)"
F_RS=$(echo "$F_OUT" | jq -r '.recommended_skill')
[[ "$F_RS" == "flow-dev" ]] && pass "F.2 recommended_skill always flow-dev" \
    || fail "F.2" "got $F_RS"

# ---------------------------------------------------------------------------
# G: SKILL.md Pre-flight guide actually references the script
# ---------------------------------------------------------------------------
echo ""
echo "G: SKILL.md Pre-flight guide"

REFCOUNT=$(grep -c "router.sh" "$SKILLMD" 2>/dev/null || echo 0)
[[ "$REFCOUNT" -ge 1 ]] && pass "G.1 SKILL.md mentions router.sh ($REFCOUNT times)" \
    || fail "G.1" "router.sh not referenced in SKILL.md"

# Accept either the old "Step 0" heading or the renamed "Pre-flight" heading.
grep -qE "^### (Pre-flight|Step 0)" "$SKILLMD" \
    && pass "G.2 SKILL.md has Pre-flight (or legacy Step 0) heading" \
    || fail "G.2" "no Pre-flight heading in SKILL.md"

# G.3 (PR-3): SKILL.md has ## Routing section.
grep -qE "^## Routing[[:space:]]*$" "$SKILLMD" \
    && pass "G.3 SKILL.md has ## Routing section (PR-3)" \
    || fail "G.3" "no ## Routing section in SKILL.md"

# ---------------------------------------------------------------------------
# H: Top-level eval runner exits 0
# ---------------------------------------------------------------------------
echo ""
echo "H: top-level eval"

bash "$EVAL" >/tmp/router-eval.out 2>&1
EVAL_RC=$?
[[ $EVAL_RC -eq 0 ]] && pass "H.1 evals/router-tests.sh exits 0" \
    || fail "H.1" "exit $EVAL_RC, output: $(cat /tmp/router-eval.out)"

# ---------------------------------------------------------------------------
# I: Spec lifecycle reaches done/ (only the final task lands done state)
# ---------------------------------------------------------------------------
echo ""
echo "I: spec lifecycle"

SPEC_DONE="$REPO_ROOT/docs/specs/done/2026-05-06-flow-dev-router-sprint1.md"
[[ -f "$SPEC_DONE" ]] && pass "I.1 spec landed in done/" \
    || fail "I.1" "$SPEC_DONE not found"

[[ ! -f "$REPO_ROOT/docs/specs/proposed/2026-05-06-flow-dev-router-sprint1.md" ]] \
    && pass "I.2 spec no longer in proposed/" \
    || fail "I.2" "spec still in proposed/"

[[ ! -f "$REPO_ROOT/docs/specs/active/2026-05-06-flow-dev-router-sprint1.md" ]] \
    && pass "I.3 spec no longer in active/" \
    || fail "I.3" "spec still in active/"

# Frontmatter status: done
if [[ -f "$SPEC_DONE" ]]; then
    if head -10 "$SPEC_DONE" | grep -q "^status: done$"; then
        pass "I.4 spec frontmatter status: done"
    else
        fail "I.4" "frontmatter status not 'done' in $SPEC_DONE"
    fi
fi

# ---------------------------------------------------------------------------
# J: rationale telemetry — diff-size string when a HEAD diff exists.
# ---------------------------------------------------------------------------
echo ""
echo "J: router rationale (diff-size telemetry)"

J1_DIR=$(mktemp -d)
( cd "$J1_DIR" && git init -q \
  && git config user.email t@t && git config user.name t \
  && git commit --allow-empty -qm init )
: > "$J1_DIR/f.txt"
for (( i=0; i<19; i++ )); do echo "line" >> "$J1_DIR/f.txt"; done
( cd "$J1_DIR" && git add f.txt )
J1_RATIONALE=$(cd "$J1_DIR" && bash "$ROUTER" "irrelevant" 2>/dev/null | jq -r '.rationale')
if [[ "$J1_RATIONALE" == "diff: 1 file, 19 lines" ]]; then
    pass "J.1 router rationale = 'diff: 1 file, 19 lines'"
else
    fail "J.1" "rationale='$J1_RATIONALE'"
fi
rm -rf "$J1_DIR"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "─────────────────────────────────────────────"
echo "integration summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "PASS Phase 3 integration" || echo "FAIL Phase 3 integration"

exit $([[ $FAIL -eq 0 ]] && echo 0 || echo 1)
