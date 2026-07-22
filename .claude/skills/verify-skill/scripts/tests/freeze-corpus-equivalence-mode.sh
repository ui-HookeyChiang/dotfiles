#!/usr/bin/env bash
# SC8 — corpus-freeze pulls from $TRUST_ROOT (merge-base origin/main HEAD),
# NOT local HEAD. Even if orchestrator committed a weakened eval to HEAD,
# the frozen copy is the pre-branch version.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main; git config user.email t@t; git config user.name t

# Step A: main has GOOD corpus (this becomes trust root)
mkdir -p sk/evals
printf -- '---\nname:sk\ndescription:x\n---\n' > sk/SKILL.md
echo '[{"q":"hard case","should_trigger":true}]' > sk/evals/trigger-eval.json
echo '[{"id":1,"prompt":"x","expected":"y"}]' > sk/test-prompts.json
git add . && git commit -q -m "good corpus on main"
git update-ref refs/remotes/origin/main HEAD
trust_root="$(git rev-parse HEAD)"

# Step B: branch and weaken corpus (commit it)
git checkout -q -b feat
echo '[{"q":"easy case","should_trigger":true}]' > sk/evals/trigger-eval.json
git add . && git commit -q -m "weaken corpus"

# Step C: also dirty the working tree
echo 'WORKING TREE EDIT' >> sk/SKILL.md

# Step D: freeze should pull from trust_root, not HEAD
RUN="$TMP/run"
"$HERE/freeze-corpus.sh" sk "$trust_root" "$RUN" >/dev/null
frozen="$(cat "$RUN/frozen-corpus/sk/evals/trigger-eval.json")"
echo "$frozen" | grep -q 'hard case' \
  || { echo "FAIL: frozen corpus contains 'easy case' (local HEAD), not 'hard case' (trust root)"; exit 1; }
echo "$frozen" | grep -q 'easy case' \
  && { echo "FAIL: frozen corpus contains weakened version"; exit 1; }
echo "PASS: freeze-corpus-equivalence-mode (SC8)"
