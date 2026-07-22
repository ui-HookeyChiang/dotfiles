#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main
git commit -q --allow-empty -m init
git remote add origin "$TMP" 2>/dev/null || true
git update-ref refs/remotes/origin/main HEAD

mkdir new-skill
cat > new-skill/SKILL.md <<'EOF'
---
name: new-skill
description: a stub
---
EOF
out="$(VERIFY_SKILL_INVOKED_BY=skill-writer SD_TRUNK_REF=origin/main "$HERE/auto-detect-mode.sh" "$TMP/new-skill")"
echo "$out" | grep -q "^mode=effect$"
echo "$out" | grep -q "^pipeline_mode=auto-pipeline-create$"
echo "PASS: auto-detect-new-skill"
