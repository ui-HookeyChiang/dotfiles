#!/usr/bin/env bash
# skill-audit/tests/two-agent-dispatch.sh
# TDD test: composer runs the deterministic leg (delegating to run.sh) and emits
# the report on STDOUT, while the 2-LLM-leg banner (probabilistic + prose) goes
# to STDERR as a NOTE. The stale per-file syntax-llm leg appears on NEITHER
# stream. SKILL_AUDIT_SKILLS_ROOT pins resolution to this checkout so the
# deterministic leg is genuinely exercised (not a masked no-op).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ERR="$(mktemp)"
out="$(SKILL_AUDIT_SKILLS_ROOT="$ROOT" python3 "$HERE/scripts/skill-audit.py" "$ROOT/skill-audit" 2>"$ERR")"
err="$(cat "$ERR")"; rm -f "$ERR"
# Banner names the 2 LLM legs ON STDERR.
echo "$err" | grep -q "probabilistic" || { echo "FAIL: no probabilistic banner on stderr"; exit 1; }
echo "$err" | grep -q "prose"         || { echo "FAIL: no prose banner on stderr"; exit 1; }
# Deterministic report reaches STDOUT (delegation to run.sh produced sections).
echo "$out" | grep -q "## deadcode"   || { echo "FAIL: deterministic report not on stdout"; exit 1; }
# Stale per-file syntax-llm leg must appear on NEITHER stream.
printf '%s\n%s\n' "$out" "$err" | grep -q "syntax-llm" && { echo "FAIL: stale syntax-llm leg still referenced"; exit 1; }
echo "PASS"
