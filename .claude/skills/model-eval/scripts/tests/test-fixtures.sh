#!/bin/sh
# Every executor fixture: buggy version fails, golden passes all tests.
set -eu
SKILL="$(cd "$(dirname "$0")/../.." && pwd)"
for tier in v1 v2 v3 v4b v4c; do
  F="$SKILL/fixtures/executor-$tier"
  D=$(mktemp -d)
  cp "$F/run-tests.sh" "$D/"
  if [ -f "$F/files.txt" ]; then files=$(cat "$F/files.txt"); else files=parse_worktree_path.sh; fi
  for f in $files; do cp "$F/$f" "$D/$f"; done
  sh "$D/run-tests.sh" >/dev/null 2>&1 && { echo "FAIL: $tier buggy fixture passes"; exit 1; }
  # apply golden: golden.<file> per source file, legacy golden.sh -> parse_worktree_path.sh
  for f in $files; do
    if [ -f "$F/golden.$f" ]; then cp "$F/golden.$f" "$D/$f"; else cp "$F/golden.sh" "$D/$f"; fi
  done
  sh "$D/run-tests.sh" >/dev/null 2>&1 || { echo "FAIL: $tier golden does not pass"; exit 1; }
  if [ -f "$F/verify-hidden.sh" ]; then
    sh "$F/verify-hidden.sh" "$D" >/dev/null 2>&1 || { echo "FAIL: $tier golden fails verify-hidden"; exit 1; }
  fi
  rm -rf "$D"
done
# v4a (stale-ticket): shipped file already passes and equals golden
F="$SKILL/fixtures/executor-v4a"; D=$(mktemp -d)
cp "$F/run-tests.sh" "$F/parse_worktree_path.sh" "$D/"
sh "$D/run-tests.sh" >/dev/null 2>&1 || { echo "FAIL: v4a shipped fixture must pass"; exit 1; }
cmp -s "$F/parse_worktree_path.sh" "$F/golden.sh" || { echo "FAIL: v4a shipped != golden"; exit 1; }
rm -rf "$D"
# v4b: shipped (buggy) file must still pass verify-hidden (guard present from start)
sh "$SKILL/fixtures/executor-v4b/verify-hidden.sh" "$SKILL/fixtures/executor-v4b" >/dev/null 2>&1 \
  || { echo "FAIL: v4b shipped fixture fails verify-hidden"; exit 1; }
python3 -c "import json; json.load(open('$SKILL/fixtures/scanner/truth.json'))"
echo "PASS test-fixtures"
# review fixture sanity: d1/d2 green, d3 green-by-cheating, d4/d6 red
for d in d1:0 d2:0 d3:0 d4:3 d6:2; do
  name=${d%:*}; want=${d#*:}
  T=$(mktemp -d); cp "$SKILL/fixtures/review/diffs/$name"/* "$T/"
  got=$(sh "$T/run-tests.sh" 2>/dev/null | tail -1 | sed 's/.*fail=//'); rm -rf "$T"
  [ "$got" = "$want" ] || { echo "FAIL: review $name expected fail=$want got fail=$got"; exit 1; }
done
python3 -c "import json; json.load(open('$SKILL/fixtures/review/truth.json')); json.load(open('$SKILL/fixtures/review/blurbs.json')); json.load(open('$SKILL/fixtures/search/questions.json')); json.load(open('$SKILL/fixtures/deep/truth.json'))"
echo "PASS test-fixtures (incl. review/search/deep)"
