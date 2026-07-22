#!/usr/bin/env bash
# integration-sprint2/test.sh — Phase 3 end-to-end integration for Sprint 2.
#
# Verifies the 3 scripts (detect-defaults, resolve-spec,
# squash-merge) all work end-to-end and that SKILL.md actually
# references them all.
#
# Usage: bash flow-dev/scripts/tests/integration-sprint2/test.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPTS="$REPO_ROOT/flow-dev/scripts"
SKILLMD="$REPO_ROOT/flow-dev/SKILL.md"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $1: $2"; }

echo "Phase 3 integration: flow-dev-script-sweep (Sprint 2)"
echo ""

# ---------------------------------------------------------------------------
# F: 3 scripts dry-run (each emits documented output)
# ---------------------------------------------------------------------------
echo "F: 3 scripts dry-run"

# F.1 detect-defaults.sh — eval round-trip
DD_OUT=$(bash "$SCRIPTS/detect-defaults.sh" "feat/integration-test")
[[ -n "$DD_OUT" ]] && pass "F.1 detect-defaults.sh emits non-empty stdout" \
    || fail "F.1" "empty stdout"

# F.2 detect-defaults.sh — eval propagates 3 vars
( eval "$DD_OUT"
  if [[ -n "${DEFAULT_BRANCH:-}" && -n "${FEATURE_PREFIX:-}" \
        && -n "${WORKTREE_NS:-}" ]]; then
    exit 0
  else
    exit 1
  fi
) && pass "F.2 detect-defaults.sh eval populates 3 vars" \
   || fail "F.2" "DEFAULT_BRANCH/FEATURE_PREFIX/WORKTREE_NS not all set"

# F.3 resolve-spec.sh — known-done spec
RS_OUT=$(bash "$SCRIPTS/resolve-spec.sh" "flow-dev-router-sprint1" 2>/dev/null)
echo "$RS_OUT" | jq . >/dev/null 2>&1 \
    && pass "F.3 resolve-spec.sh emits valid JSON" \
    || fail "F.3" "not valid JSON: $RS_OUT"

# F.4 resolve-spec.sh — all 4 keys present
RS_OK=1
for K in spec_path branch_prefix slug date; do
    HAS=$(echo "$RS_OUT" | jq -r "has(\"${K}\")")
    if [[ "$HAS" != "true" ]]; then
        RS_OK=0
        fail "F.4 resolve-spec missing key '$K'" "$(echo "$RS_OUT" | jq -c .)"
    fi
done
[[ $RS_OK -eq 1 ]] && pass "F.4 resolve-spec.sh has all 4 keys"

# F.6 squash-merge.sh stack — usage on no args (post-Sprint-3 cutover)
SM_OUT=$(bash "$SCRIPTS/squash-merge.sh" stack 2>&1 || true)
SM_RC=$?
echo "$SM_OUT" | grep -qi "usage" \
    && pass "F.6 squash-merge.sh stack exits with 'usage' on no args" \
    || fail "F.6" "expected 'usage' in output, got: $SM_OUT (rc=$SM_RC)"

# ---------------------------------------------------------------------------
# G: SKILL.md references every new script
# ---------------------------------------------------------------------------
echo ""
echo "G: SKILL.md references"

for s in detect-defaults resolve-spec squash-merge; do
    C=$(grep -c "${s}\.sh" "$SKILLMD" 2>/dev/null || echo 0)
    if [[ "$C" -ge 1 ]]; then
        pass "G.${s} SKILL.md mentions ${s}.sh ($C times)"
    else
        fail "G.${s}" "${s}.sh not referenced in SKILL.md"
    fi
done

# ---------------------------------------------------------------------------
# H: SKILL.md inline bash blocks GONE (proves replacement happened)
# ---------------------------------------------------------------------------
echo ""
echo "H: SKILL.md inline-block removal"

# H.1: the unique inline 'git symbolic-ref refs/remotes/origin/HEAD' bash
# block is gone (Phase 2 Step 1 replaced by detect-defaults.sh).
if ! grep -q "git symbolic-ref refs/remotes/origin/HEAD" "$SKILLMD"; then
    pass "H.1 inline 'git symbolic-ref refs/remotes/origin/HEAD' replaced"
else
    fail "H.1" "old inline block still present"
fi

# H.2: the inline `case "$STRATEGY" in` Jira dispatcher block is gone (~30
# lines of bash that lived in Phase 4 step 2).
if ! grep -q 'case "\$STRATEGY" in' "$SKILLMD"; then
    pass "H.2 inline Jira dispatcher case-block replaced"
else
    fail "H.2" "old Jira dispatcher case-block still present"
fi

# H.3: the inline `mapfile -t COMMITS < <(git log` from Phase 5 squash-merge
# is gone (replaced by squash-merge.sh stack).
if ! grep -q "mapfile -t COMMITS < <(git log" "$SKILLMD"; then
    pass "H.3 inline squash-merge mapfile loop replaced"
else
    fail "H.3" "old squash-merge mapfile loop still present"
fi

# ---------------------------------------------------------------------------
# I: Spec lifecycle reaches done/
# ---------------------------------------------------------------------------
echo ""
echo "I: spec lifecycle"

SPEC_DONE="$REPO_ROOT/docs/specs/done/2026-05-06-flow-dev-script-sweep.md"
[[ -f "$SPEC_DONE" ]] && pass "I.1 spec landed in done/" \
    || fail "I.1" "$SPEC_DONE not found"

[[ ! -f "$REPO_ROOT/docs/specs/proposed/2026-05-06-flow-dev-script-sweep.md" ]] \
    && pass "I.2 spec no longer in proposed/" \
    || fail "I.2" "spec still in proposed/"

[[ ! -f "$REPO_ROOT/docs/specs/active/2026-05-06-flow-dev-script-sweep.md" ]] \
    && pass "I.3 spec no longer in active/" \
    || fail "I.3" "spec still in active/"

if [[ -f "$SPEC_DONE" ]]; then
    if head -10 "$SPEC_DONE" | grep -q "^status: done$"; then
        pass "I.4 spec frontmatter status: done"
    else
        fail "I.4" "frontmatter not 'done'"
    fi
fi

# ---------------------------------------------------------------------------
# J: SKILL.md size — runaway-growth tripwire (was: Sprint 2 shrink budget).
# ---------------------------------------------------------------------------
# The original J.1/J.2 asserted the SKILL.md shrank vs the Sprint 1 head (873)
# and stayed ≤ 800 — a point-in-time gate for that one sprint. The skill has
# since grown legitimately past 800 lines through many shipped features (Gate-B
# abolition #665, TDD/dogfood residency traces, parallel-stacks, etc.), so the
# frozen shrink target is meaningless. Rather than drop size signal entirely,
# the assertion is repurposed as a GENEROUS runaway-growth tripwire: fine-grained
# size discipline lives in prose-guidelines / skill-writer audits, but a hard ceiling
# here still trips if the file ever doubles unexpectedly. Raise deliberately when
# a real feature pushes past it.
echo ""
echo "J: SKILL.md size tripwire"

LC=$(wc -l < "$SKILLMD" | tr -d ' ')
if [[ "$LC" -le 1500 ]]; then
    pass "J.1 SKILL.md within runaway-growth ceiling (≤ 1500) — now $LC"
else
    fail "J.1" "SKILL.md is $LC; exceeds runaway-growth ceiling 1500 — investigate bloat or raise the cap deliberately"
fi

# ---------------------------------------------------------------------------
# K: Existing eval suites still pass (regression guard)
# ---------------------------------------------------------------------------
echo ""
echo "K: existing eval suites pass (regression)"

bash "$REPO_ROOT/flow-dev/evals/router-tests.sh" >/tmp/sprint2-router.out 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    pass "K.1 evals/router-tests.sh exits 0"
else
    fail "K.1" "exit $RC, see /tmp/sprint2-router.out"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "─────────────────────────────────────────────"
echo "Sprint 2 integration: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "PASS Sprint 2 integration" || echo "FAIL Sprint 2 integration"

exit $([[ $FAIL -eq 0 ]] && echo 0 || echo 1)
