#!/usr/bin/env bash
# Integration test for skill-audit: end-to-end fan-out on a real skill dir.
# Asserts (1) exit 0 or 2 never 1, (2) prints the report header,
# (3) diagnostic-only — no spec file written, (4) unit suites green.
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ENTRY="$ROOT/skill-audit/scripts/skill-audit.py"
PROPOSED="$ROOT/docs/specs/proposed"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

# Snapshot proposed/ before the run so we can prove the run wrote nothing.
# Counting entries (not a fixed-name glob) catches any spec the run might emit.
before="$(ls -1 "$PROPOSED" 2>/dev/null | wc -l)"

# 1. runs end-to-end on a real skill dir, exits 0 or 2 (never 1 = engine error)
SKILL_AUDIT_SKILLS_ROOT="$ROOT" python3 "$ENTRY" "$ROOT/skill-audit" >"$OUT"; rc=$?
[ "$rc" = 0 ] || [ "$rc" = 2 ] || { echo "FAIL: exit $rc (expected 0 or 2)"; exit 1; }

# 2. prints the report header (run.sh emits ## deadcode / ## syntax / ## semantic sections)
grep -q "## deadcode" "$OUT" || { echo "FAIL: no '## deadcode' header in output"; exit 1; }

# 3. diagnostic-only: the run wrote no spec file
after="$(ls -1 "$PROPOSED" 2>/dev/null | wc -l)"
[ "$before" = "$after" ] || { echo "FAIL: skill-audit wrote a spec ($before -> $after); must be diagnostic-only"; exit 1; }

# 4. unit suites green
python3 -m pytest "$ROOT/skill-audit/scripts/tests/" -q || { echo "FAIL: unit suite"; exit 1; }

echo "PASS"
