#!/bin/sh
# Every executor fixture: buggy version fails, golden passes all tests.
set -eu
SKILL="$(cd "$(dirname "$0")/../.." && pwd)"
for tier in v1 v2 v3; do
  F="$SKILL/fixtures/executor-$tier"
  D=$(mktemp -d)
  cp "$F/run-tests.sh" "$D/"
  cp "$F/parse_worktree_path.sh" "$D/parse_worktree_path.sh"
  sh "$D/run-tests.sh" >/dev/null 2>&1 && { echo "FAIL: $tier buggy fixture passes"; exit 1; }
  cp "$F/golden.sh" "$D/parse_worktree_path.sh"
  sh "$D/run-tests.sh" >/dev/null 2>&1 || { echo "FAIL: $tier golden does not pass"; exit 1; }
  rm -rf "$D"
done
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
