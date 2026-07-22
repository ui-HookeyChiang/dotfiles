#!/usr/bin/env bash
# skill-audit/tests/refs-coverage.sh
# run.sh references/ coverage. Migrated from skill-audit's composer tests
# (test_refs_coverage.py c3/c4/c5/c8) when task-4 delegated the per-file loop to
# run.sh. These behaviors now live in run.sh, so they are asserted against its
# output. The composer-format checks (c1/c2/c6/c10) were deleted, not moved —
# run.sh emits `## syntax (path)` sections (not `#### references/x.md`), does not
# suppress F-codes on refs, and emits no deterministic G8 move-class.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FIX="$ROOT/skill-audit/scripts/tests/fixtures/refs-skill"
[ -d "$FIX" ] || { echo "SKIP: no refs-skill fixture"; exit 0; }

out="$(SKILL_AUDIT_SKILLS_ROOT="$ROOT" bash "$HERE/scripts/run.sh" "$FIX" 2>/dev/null)"

# c5: deadcode invoked exactly once (one `## deadcode` section, whole-dir).
dc_count="$(printf '%s\n' "$out" | rg -c '^## deadcode$' || true)"
[ "$dc_count" = "1" ] || { echo "FAIL c5: deadcode section count = $dc_count (expected 1)"; exit 1; }

# c3: SKILL.md F-finding survives (frontmatter finding present in SKILL.md syntax leg).
skill_syntax="$(printf '%s\n' "$out" | sed -n '/^## syntax (.*\/SKILL.md)$/,/^## semantic /p')"
printf '%s\n' "$skill_syntax" | rg -q '\bF[0-9]+\b' || { echo "FAIL c3: no F-finding under SKILL.md syntax leg"; exit 1; }

# c4: R-finding (duplicate bash block) present for references/bloated.md.
bloated_syntax="$(printf '%s\n' "$out" | sed -n '/^## syntax (.*references\/bloated.md)$/,/^## semantic /p')"
printf '%s\n' "$bloated_syntax" | rg -q '\bR[0-9]+\b' || { echo "FAIL c4: no R-finding under references/bloated.md"; exit 1; }

# c8: L1 fires for references/ghost-ref.md (scripts/ghost.sh missing), anti-blanket-suppress.
ghost_syntax="$(printf '%s\n' "$out" | sed -n '/^## syntax (.*references\/ghost-ref.md)$/,/^## semantic /p')"
printf '%s\n' "$ghost_syntax" | rg -q '\bL1\b' || { echo "FAIL c8: no L1 for ghost.sh under references/ghost-ref.md"; exit 1; }

echo "PASS"
