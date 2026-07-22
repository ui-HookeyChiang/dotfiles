#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
# Two separate repos
mkdir -p "$TMP/repo-a" "$TMP/repo-b/foreign-skill"
cd "$TMP/repo-a"; git init -q -b main; git config user.email t@t; git config user.name t
printf -- '---\nname:a\ndescription:x\n---\n' > SKILL.md; git add . && git commit -q -m init
git update-ref refs/remotes/origin/main HEAD
cd "$TMP/repo-b"; git init -q -b main; git config user.email t@t; git config user.name t
printf -- '---\nname:b\ndescription:x\n---\n' > foreign-skill/SKILL.md
cd foreign-skill && git add . && git commit -q -m init
# Symlink from repo-a to foreign-skill in repo-b
ln -s "$TMP/repo-b/foreign-skill" "$TMP/repo-a/foreign-link"

set +e
out=$(SD_TRUNK_REF=origin/main "$HERE/auto-detect-mode.sh" "$TMP/repo-a/foreign-link" 2>&1)
rc=$?
set -e
test "$rc" = "4" || { echo "expected 4 got $rc; out: $out"; exit 1; }
echo "$out" | grep -qi 'symlinked skill targets foreign repo\|foreign repo'
echo "PASS: auto-detect-symlink-foreign"
