#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main
git config user.email t@t; git config user.name t
mkdir tracked-skill
echo '---' > tracked-skill/SKILL.md
echo 'name: tracked-skill' >> tracked-skill/SKILL.md
echo 'description: x' >> tracked-skill/SKILL.md
echo '---' >> tracked-skill/SKILL.md
git add tracked-skill/SKILL.md
git commit -q -m init
git update-ref refs/remotes/origin/main HEAD
# Now dirty edit
echo 'change' >> tracked-skill/SKILL.md

out="$(VERIFY_SKILL_INVOKED_BY=skill-writer SD_TRUNK_REF=origin/main "$HERE/auto-detect-mode.sh" "$TMP/tracked-skill")"
echo "$out" | grep -q "^mode=equivalence$"
echo "$out" | grep -q "^pipeline_mode=auto-pipeline-improve$"
echo "$out" | grep -q "^trust_root=[0-9a-f]"
echo "PASS: auto-detect-dirty-skill"
