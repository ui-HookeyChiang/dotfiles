#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main
git config user.email t@t; git config user.name t
mkdir clean-skill
printf -- '---\nname: clean\ndescription: x\n---\n' > clean-skill/SKILL.md
git add . && git commit -q -m init
git update-ref refs/remotes/origin/main HEAD

out="$(SD_TRUNK_REF=origin/main "$HERE/auto-detect-mode.sh" "$TMP/clean-skill")"
echo "$out" | grep -q "^mode=effect$"
echo "$out" | grep -q "^pipeline_mode=standalone$"
echo "PASS: auto-detect-clean-skill"
