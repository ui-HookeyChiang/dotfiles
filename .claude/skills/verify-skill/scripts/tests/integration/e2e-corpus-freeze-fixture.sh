#!/usr/bin/env bash
# SC8 — full freeze-corpus chain pulls from trust root, not local HEAD.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q -b main; git config user.email t@t; git config user.name t
mkdir -p sk/evals
printf -- '---\nname: sk\ndescription: x\n---\n' > sk/SKILL.md
echo '[{"q":"trusted hard case","should_trigger":true}]' > sk/evals/trigger-eval.json
echo '[{"id":1,"prompt":"x","expected":"y"}]' > sk/test-prompts.json
git add . && git commit -q -m "trust root"
git update-ref refs/remotes/origin/main HEAD
git checkout -q -b feat
# Commit weakened corpus + edit SKILL.md
echo '[{"q":"weakened easy case","should_trigger":true}]' > sk/evals/trigger-eval.json
git add . && git commit -q -m "weaken corpus"
echo 'WT EDIT' >> sk/SKILL.md  # dirty too

RUN_DIR="$TMP/run"; mkdir -p "$RUN_DIR"
# Run auto-detect-mode → must say equivalence + auto-pipeline-improve when invoked by skill-writer
out="$(VERIFY_SKILL_INVOKED_BY=skill-writer SD_TRUNK_REF=origin/main "$HERE/auto-detect-mode.sh" "$TMP/sk")"
echo "$out" | grep -q '^mode=equivalence$'
echo "$out" | grep -q '^pipeline_mode=auto-pipeline-improve$'
trust_root="$(echo "$out" | sed -n 's/^trust_root=//p')"
skill_relpath="$(echo "$out" | sed -n 's/^skill_relpath=//p')"
test -n "$trust_root" || { echo "FAIL: empty trust_root"; exit 1; }

# Run freeze-corpus → frozen trigger-eval.json must say "trusted hard case", NOT "weakened"
"$HERE/freeze-corpus.sh" "$skill_relpath" "$trust_root" "$RUN_DIR"
frozen="$(cat "$RUN_DIR/frozen-corpus/$skill_relpath/evals/trigger-eval.json")"
echo "$frozen" | grep -q 'trusted hard case' \
  || { echo "FAIL: frozen corpus is from local HEAD not trust root"; echo "$frozen"; exit 1; }
echo "$frozen" | grep -q 'weakened easy case' \
  && { echo "FAIL: frozen corpus contains the weakened replacement"; exit 1; }

echo "PASS: e2e-corpus-freeze-fixture (SC8 end-to-end)"
