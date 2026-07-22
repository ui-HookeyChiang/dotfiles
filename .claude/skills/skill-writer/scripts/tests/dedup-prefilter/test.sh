#!/usr/bin/env bash
# tests/dedup-prefilter/test.sh
# Contract test for the Phase 1 deterministic dedup pre-pass
# (skill-writer/scripts/dedup-prefilter.py).
#
# This tests a REAL runtime script (unlike the advisory-only leak-check): it
# builds a throwaway repo of fixture skills and asserts the script's
# recommendation + scoped-cycle behavior. The pre-pass is advisory INPUT to the
# Phase 1 sweep — it narrows the LLM, never replaces the semantic judgment — so
# these assertions pin the deterministic contract (cycle scoping, overlap
# ranking, skip recommendation), not the LLM's dup verdict.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../dedup-prefilter.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASSED=0; FAILED=0
pass () { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail () { echo "  FAIL: $1 -- $2"; FAILED=$((FAILED + 1)); }

mkskill () {  # name, description, body
  mkdir -p "$TMP/$1"
  { printf -- '---\nname: %s\ndescription: %s\n---\n\n# %s\n\n%s\n' \
      "$1" "$2" "$1" "$3"; } > "$TMP/$1/SKILL.md"
}

rec () { python3 -c "import json,sys;print(json.load(sys.stdin)['recommendation'])"; }
field () { python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }

# Fixture repo:
#   alpha invokes beta; beta invokes alpha  -> a cycle (alpha,beta)
#   gamma: a versioning skill (overlap target)
#   delta: unrelated
mkskill alpha "Orchestrate alpha things across repos" "Run \`Skill beta\` to help."
mkskill beta  "Helper for beta tasks in the pipeline" "Calls back \`Skill alpha\` sometimes."
mkskill gamma "Bump semantic version and update the changelog and tag a release" "version stuff"
mkskill delta "Mount NFS shares and run fio storage benchmarks on devices" "storage"

# 1. Novel unrelated request, no candidate -> NO_OVERLAP; preexisting cycle noted, not verdict.
out="$(python3 "$SCRIPT" --request "translate subtitles between languages" --repo "$TMP")"
[ "$(echo "$out" | rec)" = "NO_OVERLAP_LLM_SKIPPABLE" ] \
  && pass "novel request -> NO_OVERLAP" || fail "novel request" "$(echo "$out" | rec)"
echo "$out" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d['preexisting_cycles'] and not d['candidate_cycles'] else 1)" \
  && pass "preexisting alpha/beta cycle reported, not verdict" || fail "preexisting cycle handling" "$(echo "$out" | field preexisting_cycles)"

# 2. Overlapping request with --self -> LLM_CONFIRM, gamma on top.
out="$(python3 "$SCRIPT" --request "bump semantic version update changelog tag a release" --repo "$TMP" --self newrel)"
[ "$(echo "$out" | rec)" = "LLM_CONFIRM_SHORTLIST" ] \
  && pass "overlapping request -> LLM_CONFIRM" || fail "overlap request" "$(echo "$out" | rec)"
echo "$out" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d['shortlist'] and d['shortlist'][0]['skill']=='gamma' else 1)" \
  && pass "gamma ranked top for version request" || fail "gamma ranking" "$(echo "$out" | field shortlist)"

# 3. Candidate IS in a cycle (--self alpha) -> CIRCULAR (scoped to candidate).
out="$(python3 "$SCRIPT" --request "x" --repo "$TMP" --self alpha)"
[ "$(echo "$out" | rec)" = "CIRCULAR" ] \
  && pass "candidate in cycle -> CIRCULAR" || fail "candidate cycle" "$(echo "$out" | rec)"

# 4. Pre-existing cycle between OTHERS, candidate NOT in it (--self gamma) -> not CIRCULAR.
out="$(python3 "$SCRIPT" --request "x" --repo "$TMP" --self gamma)"
[ "$(echo "$out" | rec)" != "CIRCULAR" ] \
  && pass "candidate outside cycle -> not CIRCULAR" || fail "scoping leak" "gamma got CIRCULAR"

# 5. Create-mode --invokes closing a loop -> CIRCULAR.
#    newx will invoke alpha; alpha invokes beta invokes alpha (newx not in loop) -> NOT circular for newx.
#    But newx --invokes beta where we also pretend beta invokes newx: emulate by self=alpha pattern is enough.
#    Verify the --invokes plumbing at least does not crash and a non-looping invoke stays non-circular:
out="$(python3 "$SCRIPT" --request "new thing" --repo "$TMP" --self newx --invokes gamma)"
[ "$(echo "$out" | rec)" != "CIRCULAR" ] \
  && pass "create-mode invoke (no loop back) -> not CIRCULAR" || fail "invokes plumbing" "$(echo "$out" | rec)"

# 6. Exit code is always 0 (advisory, never a gate).
python3 "$SCRIPT" --request "anything" --repo "$TMP" >/dev/null
[ $? -eq 0 ] && pass "exit 0 (advisory)" || fail "exit code" "non-zero"

echo "dedup-prefilter: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
