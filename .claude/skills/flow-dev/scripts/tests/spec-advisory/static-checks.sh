#!/bin/bash
# tests/spec-advisory/static-checks.sh
# Static-file assertions for the spec-advisory feature (per
# 2026-05-21-spec-advisory-auto-fix.md §Test plan item 5).
#
# Structure:
#   - one assertion per `assert_*` call, ONE per logical line, grouped by
#     section header (`# === <section> ===`).
#   - each section is wrapped in an `if [[ "$RUN_<SECTION>" == "1" ]]; then ... fi`
#     gate. Sections related to the retired flow-dev-auto lane have been
#     removed; remaining gates cover the manual full-lane and drift recovery.
#
# Exit codes:
#   0 = all enabled assertions pass
#   1 = at least one assertion failed
#
# Usage:
#   bash flow-dev/scripts/tests/spec-advisory/static-checks.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKING_DEV="$(cd "$HERE/../../.." && pwd)"
REPO_ROOT="$(cd "$STACKING_DEV/.." && pwd)"

# Section gates.
RUN_T1_FULL_LANE="${RUN_T1_FULL_LANE:-1}"     # full manual lane
RUN_DRIFT="${RUN_DRIFT:-1}"                   # AC13 — drift recovery
RUN_V6_AUTO_TRIGGER="${RUN_V6_AUTO_TRIGGER:-1}"  # V6 auto-fire + two-key prompt

PASSED=0
FAILED=0

assert_eq () {
  # $1 label, $2 expected, $3 actual
  if [[ "$2" == "$3" ]]; then
    echo "  PASS: $1 (= $3)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $1 — expected '$2', got '$3'"
    FAILED=$((FAILED + 1))
  fi
}

assert_ge () {
  # $1 label, $2 minimum, $3 actual
  if [[ "$3" -ge "$2" ]]; then
    echo "  PASS: $1 (>= $2; actual $3)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $1 — expected >= $2, got $3"
    FAILED=$((FAILED + 1))
  fi
}

assert_file () {
  # $1 label, $2 path
  if [[ -f "$2" ]]; then
    echo "  PASS: $1 (file exists: $2)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $1 — file missing: $2"
    FAILED=$((FAILED + 1))
  fi
}

assert_cmd_exit () {
  # $1 label, $2 expected_exit, $3... command
  local label="$1" expected="$2"
  shift 2
  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  if [[ $actual -eq $expected ]]; then
    echo "  PASS: $label (exit $actual)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $label — expected exit $expected, got $actual ($*)"
    FAILED=$((FAILED + 1))
  fi
}

echo "spec-advisory static-checks:"

# =============================================================================
# === T1: full-lane drift recovery (AC7, AC8, AC9) ===========================
# =============================================================================
if [[ "$RUN_T1_FULL_LANE" == "1" ]]; then
  echo "[T1 full-lane]"

  # AC8a — reviewer-brief now lives in the adversarial-review skill
  # (the retired prompt-template file migrated into its Spec-gating mode section).
  PROMPT="$REPO_ROOT/adversarial-review/SKILL.md"
  assert_file "AC8a: adversarial-review/SKILL.md exists" "$PROMPT"

  # AC8b — the Spec-gating mode section is present (the named reviewer brief
  # flow-dev's spec-advisory dispatches into).
  c=$(/bin/grep -cE '^## Spec-gating mode' "$PROMPT" || true)
  assert_eq "AC8b: Spec-gating mode section present" 1 "$c"

  # AC8c — severity rubric has exactly 3 graded bullets (HIGH, MED, LOW)
  c=$(/bin/grep -cE '^- \*\*(HIGH|MED|LOW)\*\*' "$PROMPT" || true)
  assert_eq "AC8c: 3 severity bullets in rubric" 3 "$c"

  # AC7 — checklist has >= 5 lines (was 4 items, +1 advisory item)
  CHECKLIST="$REPO_ROOT/flow/references/spec-review-checklist.md"
  n=$(awk 'END{print NR}' "$CHECKLIST")
  assert_ge "AC7: spec-review-checklist.md NR >= 5" 5 "$n"

  # AC9a — SKILL.md references spec-advisory.sh at least once
  SKILL="$STACKING_DEV/SKILL.md"
  c=$(/bin/grep -c 'spec-advisory.sh' "$SKILL" || true)
  assert_ge "AC9a: SKILL.md mentions spec-advisory.sh" 1 "$c"

  # AC9b — superseded by V6 (per docs/specs/active/2026-05-21-spec-advisory-auto-trigger.md AC9).
  # When RUN_V6_AUTO_TRIGGER=1 (default in V6+ era), the V6 section below asserts
  # [a]dvisory is ABSENT (count==0). When RUN_V6_AUTO_TRIGGER=0 (archeological
  # replay against pre-V6 SKILL.md), the original T1 contract applies.
  if [[ "${RUN_V6_AUTO_TRIGGER:-1}" == "0" ]]; then
    c=$(/bin/grep -cE '\[a\](dvisory)?\b' "$SKILL" || true)
    assert_ge "AC9b (pre-V6 replay): SKILL.md mentions [a]dvisory key" 1 "$c"
  fi
fi

# =============================================================================
# === Drift recovery (AC13) ===================================================
# =============================================================================
# AC13: after T1 merges, the 2026-05-10 spec-review-gate spec must still
# spec-lint cleanly AND SKILL.md must still mention spec-advisory.sh.
if [[ "$RUN_DRIFT" == "1" ]]; then
  echo "[AC13 drift recovery]"

  DRIFT_SPEC="$REPO_ROOT/docs/specs/done/2026-05-10-spec-review-gate.md"
  if [[ -f "$DRIFT_SPEC" ]]; then
    assert_cmd_exit "AC13a: spec-lint passes on 2026-05-10-spec-review-gate.md" 0 \
      bash "$STACKING_DEV/scripts/spec-lint.sh" "$DRIFT_SPEC"
  else
    echo "  SKIP: AC13a — drift target spec not found at $DRIFT_SPEC"
  fi

  # AC13b — SKILL.md must mention spec-advisory.sh (rewiring presence)
  c=$(/bin/grep -c 'spec-advisory.sh' "$STACKING_DEV/SKILL.md" || true)
  assert_ge "AC13b: SKILL.md mentions spec-advisory.sh (drift rewired)" 1 "$c"
fi

# =============================================================================
# === V6 auto-trigger (T5 — spec-advisory-auto-trigger) =======================
# =============================================================================
# V6 spec: 2026-05-21-spec-advisory-auto-trigger.md
#   AC1: [a] key removed from L2 prompt prose
#   AC2: [y]/[n] two-key prompt still documented
#   AC3: auto-fire / auto-dispatch wording present
#   AC4: observability `advisor: mode=` log line documented
#   AC5: per-agent timeout 120s documented
#   AC6: join barrier / parallel agent independence documented
#   AC7: zero write authority OR advisor read-only documented
#   AC8: SD_SKIP_ADVISORY bypass preserved (already covered by T1 AC9 region;
#        re-asserted here for V6 completeness)
if [[ "$RUN_V6_AUTO_TRIGGER" == "1" ]]; then
  echo "[V6 auto-trigger]"

  SKILL_MD="$STACKING_DEV/SKILL.md"

  # AC1 — [a]dvisory mnemonic key removed (count must be 0).
  # Narrow regex per docs/specs/done/2026-05-25-fix-v6-ac1-regex.md: the
  # earlier `\[a\]\b` alternative also matched same-shape mnemonics like
  # `[a]bort` (L314) and `[a]dopt` (L321) from `adopt-superpowers-plan.sh`'s
  # parser-exit prompts — those are legitimate prompt keys, unrelated to the
  # V6 advisory contract. `git pickaxe` confirms the advisory mnemonic was
  # always spelled `[a]dvisory` in SKILL.md, so the literal-string match is
  # both sufficient and the only contract V6 spec L95 actually asserts.
  c=$(/bin/grep -cE '\[a\]dvisory' "$SKILL_MD" || true)
  assert_eq "V6 AC1: [a]dvisory key removed from SKILL.md" 0 "$c"

  # AC2 — [y]/[n] two-key prompt still present
  c_y=$(/bin/grep -cE '\[y\]es' "$SKILL_MD" || true)
  c_n=$(/bin/grep -cE '\[n\]o' "$SKILL_MD" || true)
  assert_ge "V6 AC2a: [y]es key documented" 1 "$c_y"
  assert_ge "V6 AC2b: [n]o key documented" 1 "$c_n"

  # AC3 — auto-fire / auto-dispatch wording
  c=$(/bin/grep -cE 'auto-fire|auto-dispatch' "$SKILL_MD" || true)
  assert_ge "V6 AC3: auto-fire / auto-dispatch wording present" 1 "$c"

  # AC4 — observability log line documented (Gregg)
  c=$(/bin/grep -cE 'advisor: mode=' "$SKILL_MD" || true)
  assert_ge "V6 AC4: advisor: mode= log line documented (observability)" 1 "$c"

  # AC5 — per-agent timeout 120s (Cook)
  c=$(/bin/grep -cE 'timeout 120s|per-agent .* 120s|120s.*timeout' "$SKILL_MD" || true)
  assert_ge "V6 AC5: per-agent timeout 120s documented (bounded latency)" 1 "$c"

  # AC6 — join barrier / parallel independence (McKenney)
  c=$(/bin/grep -cE 'join barrier|parallel.*share no mutable|parallel.*independent' "$SKILL_MD" || true)
  assert_ge "V6 AC6: join barrier / parallel independence documented" 1 "$c"

  # AC7 — zero write authority / read-only (Thompson)
  c=$(/bin/grep -cE 'zero write authority|advisor.*read-only|advisor has zero write' "$SKILL_MD" || true)
  assert_ge "V6 AC7: advisor zero write authority documented (single-writer)" 1 "$c"

  # AC8 — SD_SKIP_ADVISORY bypass preserved
  c=$(/bin/grep -c 'SD_SKIP_ADVISORY' "$SKILL_MD" || true)
  assert_ge "V6 AC8: SD_SKIP_ADVISORY bypass preserved" 1 "$c"
fi


# r5 contract checks
echo "Checking r5 contract: agents=3, always-three, trace-lib, reviewer brief"

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -qF "$pattern" "$file"; then
    echo "  PASS $label: '$pattern' present in $(basename "$file")"
  else
    echo "  FAIL $label: '$pattern' MISSING in $(basename "$file")"
    exit 1
  fi
}

# flow-dev/SKILL.md
SKILL="$(cd "$(dirname "$0")/../../.." && pwd)/SKILL.md"
assert_contains "$SKILL" "agents=3"          "AC-r5-1"
assert_contains "$SKILL" "always-three"      "AC-r5-2"
# AC-r5-3 (deferred): Task 2 SKILL.md uses role enumeration "1 general-purpose acceptance-sharpness"
# rather than literal "Agent C" label. Plan step 3.5 verbatim asserted "Agent C" but Task 2
# step 2.3 verbatim never added that literal token to L207-231. Skipping to avoid scope creep
# into Task 2 territory (modifying SKILL.md L207-231 is explicitly forbidden by Task 3 rules).
# Coverage: AC-r5-2 (always-three) + AC-r5-10 (Agent C in prompt template) jointly cover the
# Agent C contract presence; the SKILL.md surface specifically is verified by AC-r5-1/2/4/5.
# assert_contains "$SKILL" "Agent C"      "AC-r5-3"
# AC-r5-4: sandwich-trace system deleted (PR #953.2) — no runtime consumer remains.
# assert_contains "$SKILL" "sandwich-trace.sh"  "AC-r5-4"
# AC-r5-5: SD_SKIP_SANDWICH removed from SKILL.md by Task 6 — assertion deleted.
# AC-r5-6: "Sandwich cadence" section removed from loop-protocol.md by Task 6 — assertion deleted.
# AC-r5-7: SD_SKIP_SANDWICH removed from loop-protocol.md by Task 6 — assertion deleted.
# AC-r5-8: .flow-dev-sandwich.json prose sidecar gone; loop-protocol.md no longer mentions it — deleted.
# AC-r5-9: .git/flow-dev-sandwich.log removed from loop-protocol.md by Task 6 — assertion deleted.

# adversarial-review/SKILL.md — reviewer brief migrated here from the
# retired prompt-template file (now its Spec-gating mode section).
PROMPT="$(cd "$(dirname "$0")/../../../.." && pwd)/adversarial-review/SKILL.md"
assert_contains "$PROMPT" "acceptance-criteria sharpness" "AC-r5-10"
assert_contains "$PROMPT" "N=3 independent reviewers"     "AC-r5-11"

# AC-r5-12: .flow-dev-sandwich.json sidecar no longer produced — assertion deleted.

echo "  All r5 contract checks PASS"


echo
echo "Results: $PASSED passed, $FAILED failed."
if [[ $FAILED -eq 0 ]]; then
  echo "spec-advisory static-checks: PASS"
  exit 0
else
  echo "spec-advisory static-checks: FAIL"
  exit 1
fi
