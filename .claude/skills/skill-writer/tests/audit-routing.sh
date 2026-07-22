#!/usr/bin/env bash
# audit-routing.sh — regression: skill-writer/SKILL.md must name no deleted
# engine and must name both surviving engines.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_MD="$REPO/skill-writer/SKILL.md"

pass=0
fail=0

check_absent() {
    local name="$1"
    if grep -qF "$name" "$SKILL_MD"; then
        echo "FAIL: '$name' still present in skill-writer/SKILL.md" >&2
        fail=$((fail + 1))
    else
        echo "PASS: '$name' absent from skill-writer/SKILL.md"
        pass=$((pass + 1))
    fi
}

check_present() {
    local name="$1"
    if grep -qF "$name" "$SKILL_MD"; then
        echo "PASS: '$name' present in skill-writer/SKILL.md"
        pass=$((pass + 1))
    else
        echo "FAIL: '$name' missing from skill-writer/SKILL.md" >&2
        fail=$((fail + 1))
    fi
}

check_absent "skill-syntax-audit"
check_absent "skill-semantic-audit"
check_absent "skill-deadcode-audit"
check_absent "skill-deterministic-audit"
check_absent "skill-probabilistic-audit"
check_present "skill-audit"

# prose-guidelines is a SURVIVING skill that routes to the audit engines; guard
# every line against the deleted names EXCEPT genuine past-tense history prose
# (lines marked "retired" / "used to live" / "successor" / "was"). Any other
# mention — a "Use `...`" row, a sibling-audit table row, a References path — is a
# live routing regression and must fail.
PROSE_MD="$REPO/prose-guidelines/SKILL.md"
HISTORY_RE='retired|used to live|successor|\bwas\b|replaced'
check_prose_routing_clean() {
    local name="$1"
    # Lines naming the deleted engine that are NOT history prose.
    local hits
    hits=$(grep -nF "$name" "$PROSE_MD" | grep -ivE "$HISTORY_RE" || true)
    if [ -n "$hits" ]; then
        echo "FAIL: prose-guidelines has live (non-history) ref to deleted '$name':" >&2
        echo "$hits" >&2
        fail=$((fail + 1))
    else
        echo "PASS: prose-guidelines has no live ref to deleted '$name' (history-only)"
        pass=$((pass + 1))
    fi
}
check_prose_routing_clean "skill-syntax-audit"
check_prose_routing_clean "skill-semantic-audit"
check_prose_routing_clean "skill-deadcode-audit"
if grep -qF "skill-audit" "$PROSE_MD"; then
    echo "PASS: prose-guidelines names the unified skill-audit"
    pass=$((pass + 1))
else
    echo "FAIL: prose-guidelines missing skill-audit name" >&2
    fail=$((fail + 1))
fi

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
    exit 1
fi
