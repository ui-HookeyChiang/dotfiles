#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
mkdir -p "$TMP/has spaces/my-skill"
cd "$TMP/has spaces"
git init -q -b main
git config user.email t@t; git config user.name t
printf -- '---\nname: x\ndescription: x\n---\n' > my-skill/SKILL.md
git add . && git commit -q -m init
git update-ref refs/remotes/origin/main HEAD

out="$(SD_TRUNK_REF=origin/main "$HERE/auto-detect-mode.sh" "$TMP/has spaces/my-skill")"
echo "$out" | grep -q "^mode=effect$"
echo "PASS: auto-detect-spaces-in-path"
