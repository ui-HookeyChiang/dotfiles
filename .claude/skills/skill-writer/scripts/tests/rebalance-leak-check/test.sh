#!/usr/bin/env bash
# tests/rebalance-leak-check/test.sh
# Contract test for the Phase 3-ref HOLD-IN-PLACE leak check (rewrite mode).
#
# HONEST FRAMING (anti-self-grading, per spec criterion 2):
#   The production leak check is a DOCUMENTED ADVISORY step — there is NO
#   runtime script in the rewrite flow that runs this. The real, BINDING grader
#   is verify-skill Phase 6 (A2/A4 voters re-grading the v2 disclosure surface).
#   The `leak_check()` below is a small grep-based helper authored IN this test;
#   it pins the *contract shape* the documented detector is specified to have:
#       planted-leak -> flagged, clean -> pass, override -> widened (relocation
#       flagged), no-v1-snapshot -> clean no-op.
#   It proves the detector behaves as specified — NOT that skill-creator or the
#   advisory scan actually fires in a real rewrite. Do NOT read a pass here as
#   evidence the scan ran. (The audit signal for "it ran" is the
#   gate=content-placement / references: traces, not this fixture.)
#
# Exits non-zero on any contract violation (so a future edit that silently
# guts the leak-check contract fails CI).
set -euo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASSED=0
FAILED=0
pass () { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail () { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

# --- detector: a HOLD-IN-PLACE marker present in v1 SKILL.md must still be in
# v2 SKILL.md (not relocated into references/). Returns 0 = clean, 1 = leak.
#
# Two marker classes (per spec §2):
#   - intrinsic HOLD-IN-PLACE (gate tables, NEVER-clauses): always tracked.
#   - routing blocks: MIGRATE-eligible by default, so relocating them is
#     legitimate — UNLESS the orchestrator override marker
#     `standard-override: disclosure-rule-5` is present in v1 SKILL.md
#     frontmatter, which WIDENS HOLD-IN-PLACE to cover routing and pins it.
# The override is therefore the discriminator: the detector must READ it to
# decide whether the routing block is trackable at all.
#
# $5 (require_override) is optional: when "1", the marker is only treated as
# HOLD-IN-PLACE if the override is present in v1 SKILL.md frontmatter (routing
# semantics). When absent/"0", the marker is intrinsic HOLD-IN-PLACE.
leak_check() {
  local v1_skill="$1" v2_skill="$2" v2_refs_dir="$3" marker="$4"
  local require_override="${5:-0}"
  # No v1 snapshot (create/modify, or tampered) -> nothing to compare -> clean.
  [[ -f "$v1_skill" ]] || return 0
  # Marker absent from v1 -> not a HOLD-IN-PLACE item we track -> clean.
  grep -qF "$marker" "$v1_skill" || return 0
  # Routing-class marker: only HOLD-IN-PLACE when the override widens it.
  # Read the override marker from v1 frontmatter; absent -> MIGRATE-eligible,
  # so relocation is legitimate -> clean (NOT tracked as a leak).
  if [[ "$require_override" == "1" ]]; then
    grep -qF "$OVERRIDE" "$v1_skill" || return 0
  fi
  # Held in place (still in v2 SKILL.md) -> clean, even if also in references/.
  if [[ -f "$v2_skill" ]] && grep -qF "$marker" "$v2_skill"; then
    return 0
  fi
  # Not in v2 SKILL.md but present under v2 references/ -> leaked.
  if grep -rqF "$marker" "$v2_refs_dir" 2>/dev/null; then
    return 1
  fi
  # Removed entirely (not in v2 SKILL.md nor references/) -> not a leak.
  return 0
}

MARKER="| gate=spec-advisory | MANDATORY | HARD STOP |"   # representative gate-table row
ROUTING_MARKER="| route | dispatch-target |"     # representative routing row
OVERRIDE="standard-override: disclosure-rule-5"   # SKILL.md frontmatter marker

# --- Case 1: LEAK — gate table moved from v1 SKILL.md into v2 references/ -----
case_leak () {
  mkdir -p "$TMP/leak/v2refs"
  printf '# Skill\n%s\nbody\n' "$MARKER"      > "$TMP/leak/v1.md"
  printf '# Skill\nbody only\n'               > "$TMP/leak/v2.md"
  printf 'detail\n%s\n' "$MARKER"             > "$TMP/leak/v2refs/phase.md"
  if leak_check "$TMP/leak/v1.md" "$TMP/leak/v2.md" "$TMP/leak/v2refs" "$MARKER"; then
    fail "Case 1 LEAK: gate-table relocation into references/ not detected"
  else
    pass "Case 1 LEAK: gate-table relocation into references/ detected"
  fi
}

# --- Case 2: CLEAN — gate table held in v2 SKILL.md --------------------------
case_clean () {
  mkdir -p "$TMP/clean/v2refs"
  printf '# Skill\n%s\nbody\n' "$MARKER"      > "$TMP/clean/v1.md"
  printf '# Skill\n%s\nslimmer\n' "$MARKER"   > "$TMP/clean/v2.md"
  printf 'migrated derivation only\n'         > "$TMP/clean/v2refs/phase.md"
  if leak_check "$TMP/clean/v1.md" "$TMP/clean/v2.md" "$TMP/clean/v2refs" "$MARKER"; then
    pass "Case 2 CLEAN: held-in-place gate table passes"
  else
    fail "Case 2 CLEAN: held-in-place gate table wrongly flagged"
  fi
}

# --- Case 3: create/modify no-op — no v1 snapshot (rewrite-mode-only) --------
# The check is rewrite-mode only. Absent a v1 snapshot the detector must not
# error and must report clean (never blocks create/modify).
case_noop () {
  if leak_check "/nonexistent/v1.md" "$TMP/clean/v2.md" "$TMP/clean/v2refs" "$MARKER" 2>/dev/null; then
    pass "Case 3 NO-OP: missing v1 snapshot (create/modify) is a clean no-op"
  else
    fail "Case 3 NO-OP: missing v1 snapshot should not error / should be clean"
  fi
}

# --- Case 4: ORCHESTRATOR-OVERRIDE CONTRAST — the override is the discriminator
# 4a and 4b relocate the SAME routing block from v1 SKILL.md into v2
# references/. They differ in EXACTLY ONE thing: whether the v1 frontmatter
# carries `standard-override: disclosure-rule-5`.
#   4a (override PRESENT): the override WIDENS HOLD-IN-PLACE to cover routing,
#       so relocating the routing block is a LEAK -> flagged.
#   4b (override ABSENT):  routing is MIGRATE-eligible by default, so the SAME
#       relocation is legitimate -> NOT flagged.
# Routing-class markers are checked with require_override=1, so the detector
# must READ the override from frontmatter to reach opposite verdicts. If it
# ignored the override, 4a and 4b would be identical (tautology) — and 4a would
# fail under a stub that always treats routing as migratable.
case_override_present () {
  mkdir -p "$TMP/ov_present/v2refs"
  printf -- '---\n%s\n---\n# Orchestrator\n%s\nbody\n' "$OVERRIDE" "$ROUTING_MARKER" \
                                              > "$TMP/ov_present/v1.md"
  printf -- '---\n%s\n---\n# Orchestrator\nbody only\n' "$OVERRIDE" \
                                              > "$TMP/ov_present/v2.md"
  printf 'routing detail\n%s\n' "$ROUTING_MARKER" \
                                              > "$TMP/ov_present/v2refs/routing.md"
  if leak_check "$TMP/ov_present/v1.md" "$TMP/ov_present/v2.md" "$TMP/ov_present/v2refs" "$ROUTING_MARKER" 1; then
    fail "Case 4a OVERRIDE PRESENT: override-widened routing relocation not detected"
  else
    pass "Case 4a OVERRIDE PRESENT: override-widened routing relocation flagged as leak"
  fi
}

case_override_absent () {
  mkdir -p "$TMP/ov_absent/v2refs"
  # SAME routing block + SAME relocation as 4a, but NO override in frontmatter.
  printf -- '---\ntitle: plain\n---\n# Plain\n%s\nbody\n' "$ROUTING_MARKER" \
                                              > "$TMP/ov_absent/v1.md"
  printf -- '---\ntitle: plain\n---\n# Plain\nbody only\n' \
                                              > "$TMP/ov_absent/v2.md"
  printf 'routing detail\n%s\n' "$ROUTING_MARKER" \
                                              > "$TMP/ov_absent/v2refs/routing.md"
  if leak_check "$TMP/ov_absent/v1.md" "$TMP/ov_absent/v2.md" "$TMP/ov_absent/v2refs" "$ROUTING_MARKER" 1; then
    pass "Case 4b OVERRIDE ABSENT: routing is MIGRATE-eligible, relocation not flagged"
  else
    fail "Case 4b OVERRIDE ABSENT: routing relocation wrongly flagged without override"
  fi
}

case_leak
case_clean
case_noop
case_override_present
case_override_absent

echo
echo "rebalance leak-check contract: $PASSED passed, $FAILED failed"
if [[ $FAILED -eq 0 ]]; then
  echo "PASS: rebalance leak-check contract"
else
  exit 1
fi
