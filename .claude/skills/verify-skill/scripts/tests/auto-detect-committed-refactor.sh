#!/usr/bin/env bash
# Test: committed refactor on a feature branch → mode=equivalence
# Bug proof: before the fix, working-tree diff vs HEAD is empty → falls to effect.
# The correct base is merge-base(origin/main, HEAD) = TRUST_ROOT.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main
git config user.email t@t; git config user.name t

# Commit the skill on main — this becomes origin/main (the trust root)
mkdir my-skill
printf -- '---\nname: my-skill\ndescription: original\n---\n' > my-skill/SKILL.md
git add my-skill/SKILL.md
git commit -q -m "add my-skill"
git update-ref refs/remotes/origin/main HEAD

# Create a feature branch and commit a refactor (working tree is CLEAN after commit)
git checkout -q -b feature/refactor
printf -- '---\nname: my-skill\ndescription: refactored\n---\n# Body\nsome new content\n' > my-skill/SKILL.md
git add my-skill/SKILL.md
git commit -q -m "refactor my-skill"

# Working tree must be clean so the buggy vs-HEAD path fires
git diff --quiet HEAD -- my-skill/SKILL.md  # assert clean

out="$(SD_TRUNK_REF=origin/main "$HERE/auto-detect-mode.sh" "$TMP/my-skill")"
echo "$out" | grep -q "^mode=equivalence$" \
  || { echo "FAIL: expected mode=equivalence, got:"; echo "$out"; exit 1; }
echo "$out" | grep -q "^trust_root=[0-9a-f]"
echo "PASS: auto-detect-committed-refactor"
