#!/usr/bin/env bash
# skill-audit/scripts/run.sh <skill-dir>
# Deterministic audit: deadcode + syntax-metrics + semantic-rule-prefilter.
# Pure script, no LLM, no agent dispatch. Exit 0=problem 2=clean 1=error.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="${1:?usage: run.sh <skill-dir>}"
SKILL_MD="$SKILL_DIR/SKILL.md"
any_problem=0; any_error=0

echo "## deadcode"
python3 "$HERE/reachability.py" "$SKILL_DIR"
rc=$?; [ "$rc" = 0 ] && any_problem=1; [ "$rc" = 1 ] && any_error=1

# syntax-metrics + semantic-prefilter run per file over SKILL.md ∪ references/*.md
mapfile -t TARGETS < <(printf '%s\n' "$SKILL_MD"; \
  fdfind -e md -d 1 . "$SKILL_DIR/references" 2>/dev/null | sort)
for t in "${TARGETS[@]}"; do
  [ -f "$t" ] || continue
  is_ref=0; [ "$t" != "$SKILL_MD" ] && is_ref=1
  echo "## syntax ($t)"
  if [ "$is_ref" = 1 ]; then
    bash "$HERE/syntax_audit.sh" "$t" --no-spec --skill-root "$SKILL_DIR"
  else
    bash "$HERE/syntax_audit.sh" "$t" --no-spec
  fi
  rc=$?; [ "$rc" = 0 ] && any_problem=1; [ "$rc" = 1 ] && any_error=1
  echo "## semantic ($t)"
  # G1 scoped to THIS skill only (no --cross corpus); G8 SKILL.md-only by nature.
  if [ "$is_ref" = 1 ]; then
    bash "$HERE/semantic_audit.sh" "$t" --no-llm --axis G1
  else
    bash "$HERE/semantic_audit.sh" "$t" --no-llm
  fi
  rc=$?; [ "$rc" = 0 ] && any_problem=1; [ "$rc" = 1 ] && any_error=1
done

[ "$any_error" = 1 ] && exit 1
[ "$any_problem" = 1 ] && exit 0
exit 2
