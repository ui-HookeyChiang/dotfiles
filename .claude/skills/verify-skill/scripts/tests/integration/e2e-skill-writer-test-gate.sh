#!/usr/bin/env bash
# SC3 — skill-writer TEST stage maps verify-skill exit codes to PASS/BLOCK/STOP.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT

# Test the preflight script — must exit 0 if verify-skill symlink exists,
# exit 2 with remediation otherwise.
if [[ -f "$HOME/.claude/skills/verify-skill/SKILL.md" || -f "$HOME/.agents/skills/verify-skill/SKILL.md" ]]; then
  bash "$REPO_ROOT/skill-writer/scripts/check-verify-skill.sh" || { echo "FAIL: preflight should pass when installed"; exit 1; }
  echo "PASS: check-verify-skill exits 0 when installed"
else
  set +e
  bash "$REPO_ROOT/skill-writer/scripts/check-verify-skill.sh" 2>"$TMP/err"
  rc=$?
  set -e
  test "$rc" = "2" || { echo "FAIL: expected exit 2 when not installed, got $rc"; exit 1; }
  grep -q remediation "$TMP/err" || { echo "FAIL: missing remediation hint"; exit 1; }
  echo "PASS: check-verify-skill exits 2 + remediation when not installed"
fi

# Spot-check skill-writer SKILL.md has TEST stage section
grep -q '^## Stage 3 — TEST' "$REPO_ROOT/skill-writer/SKILL.md" \
  || { echo "FAIL: skill-writer/SKILL.md missing Stage 3 TEST section"; exit 1; }
grep -q 'VERIFY_SKILL_INVOKED_BY=skill-writer' "$REPO_ROOT/skill-writer/SKILL.md" \
  || { echo "FAIL: TEST stage missing env injection"; exit 1; }
grep -q 'verify-skill 5-voter' "$REPO_ROOT/skill-writer/SKILL.md" \
  || { echo "FAIL: TEST stage missing verify-skill gate"; exit 1; }

# Spot-check that --mode override is forbidden. (Plan literal was
# `Do NOT pass \`--mode\`` but SKILL.md inlines the arg form
# `\`--mode <effect|equivalence>\`` — match the actual phrasing.)
grep -q 'Do NOT pass `--mode' "$REPO_ROOT/skill-writer/SKILL.md" \
  || { echo "FAIL: TEST stage missing --mode prohibition"; exit 1; }

echo "PASS: e2e-skill-writer-test-gate (SC3 wiring)"
