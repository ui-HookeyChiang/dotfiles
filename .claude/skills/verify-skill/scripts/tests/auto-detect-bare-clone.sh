#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q --bare bare.git
mkdir bare.git/some-skill
echo '---' > bare.git/some-skill/SKILL.md
set +e
"$HERE/auto-detect-mode.sh" "$TMP/bare.git/some-skill" 2>/dev/null
rc=$?
set -e
test "$rc" = "4" || { echo "expected 4 got $rc"; exit 1; }
echo "PASS: auto-detect-bare-clone"
