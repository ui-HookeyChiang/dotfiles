#!/bin/bash
# tests/resolve-spec/test.sh - per-script tests for resolve-spec.sh.
#
# Asserts resolve-spec.sh behavior under the only surviving backend (none),
# after the docs-lifecycle backend was removed. The dead has_lifecycle_config
# / lifecycle output fields were dropped in the v4 router cleanup; spec_path
# is populated only by globbing docs/superpowers/specs/*-<slug>-design.md
# (no repo-root config, no lifecycle states, no SD_SPEC_PATH override).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../resolve-spec.sh"

FAILED=0

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [[ "$expected" == "$actual" ]]; then
    echo "  ok   $name"
  else
    echo "  FAIL $name: expected='$expected' actual='$actual'"
    FAILED=1
  fi
}

assert_zero() {
  local name=$1 rc=$2
  if (( rc == 0 )); then
    echo "  ok   $name"
  else
    echo "  FAIL $name: exit=$rc"
    FAILED=1
  fi
}

echo "behavioral cases:"

# 1. Real spec on disk resolves under none (positive glob path). Hermetic:
#    author a spec under docs/superpowers/specs/ in a scratch CWD so the test
#    does not depend on this repo's own (movable) spec files. The none backend
#    globs *-<slug>-design.md, parses the YYYY-MM-DD date from the filename,
#    and parses the date from the filename. (The dead has_lifecycle_config /
#    lifecycle output fields were dropped in the v4 router cleanup.)
SCRATCH1="$(mktemp -d)"
mkdir -p "$SCRATCH1/docs/superpowers/specs"
: > "$SCRATCH1/docs/superpowers/specs/2026-05-06-resolve-fixture-design.md"
echo "# fixture" > "$SCRATCH1/docs/superpowers/specs/2026-05-06-resolve-fixture-design.md"
OUT1="$(cd "$SCRATCH1" && bash "$SCRIPT" resolve-fixture)"
rm -rf "$SCRATCH1"
SP1="$(jq -r '.spec_path' <<<"$OUT1")"
if [[ "$SP1" == "docs/superpowers/specs/2026-05-06-resolve-fixture-design.md" ]]; then
  echo "  ok   1c .spec_path globbed under docs/superpowers/specs/"
else
  echo "  FAIL 1c .spec_path unexpected: '$SP1'"; FAILED=1
fi
assert_eq "1d .slug==resolve-fixture" \
  "resolve-fixture" "$(jq -r '.slug' <<<"$OUT1")"
assert_eq "1e .date==2026-05-06 (parsed from filename)" \
  "2026-05-06" "$(jq -r '.date' <<<"$OUT1")"

# 2. Nonexistent slug graceful (no match -> empty path).
OUT2="$(bash "$SCRIPT" nonexistent-slug-xyz)"
assert_eq "2b .spec_path==''" \
  "" "$(jq -r '.spec_path' <<<"$OUT2")"
assert_eq "2c .slug==nonexistent-slug-xyz" \
  "nonexistent-slug-xyz" "$(jq -r '.slug' <<<"$OUT2")"

# 3. SD_SPEC_PATH override is a NO-OP under none. That env var only
#    short-circuited the (now-removed) docs-lifecycle backend; the none
#    backend scans by slug glob only and never honors it. spec_path therefore
#    stays empty for a slug with no on-disk spec. (Old behavior surfaced
#    /tmp/x.md verbatim; this asserts the override no longer leaks through.)
OUT3="$(SD_SPEC_PATH=/tmp/x.md bash "$SCRIPT" anything)"
assert_eq "3a .spec_path=='' (SD_SPEC_PATH ignored under none)" \
  "" "$(jq -r '.spec_path' <<<"$OUT3")"
assert_eq "3b .slug==anything" \
  "anything" "$(jq -r '.slug' <<<"$OUT3")"

# 4. tmpdir without .docs-lifecycle.json (still exits 0, emits valid JSON).
TMP="$(mktemp -d)"
OUT4="$(cd "$TMP" && bash "$SCRIPT" foo; echo "RC=$?")"
RC4="${OUT4##*RC=}"
JSON4="${OUT4%RC=*}"
rm -rf "$TMP"
assert_eq "4a .slug==foo" \
  "foo" "$(jq -r '.slug' <<<"$JSON4")"
assert_eq "4b exit 0" "0" "$RC4"

# 5. Output is valid JSON (jq . round-trip exits 0).
bash "$SCRIPT" x | jq . >/dev/null 2>&1
assert_zero "5 valid JSON (jq .)" $?

# 6. All 4 keys present (jq has() for each).
OUT6="$(bash "$SCRIPT" x)"
for KEY in spec_path branch_prefix slug date; do
  HAS="$(jq -r --arg k "$KEY" 'has($k)' <<<"$OUT6")"
  assert_eq "6 has(\"$KEY\")" "true" "$HAS"
done

echo "structural checks:"

# 7a. wc -l <= 130.
LINES=$(wc -l < "$SCRIPT" | tr -d ' ')
if (( LINES <= 130 )); then
  echo "  ok   7a line-count ($LINES <= 130)"
else
  echo "  FAIL 7a line-count: $LINES > 130"; FAILED=1
fi

# 7b. shebang.
FIRST="$(head -n1 "$SCRIPT")"
if [[ "$FIRST" == \#!* ]]; then
  echo "  ok   7b shebang present"
else
  echo "  FAIL 7b shebang: first line='$FIRST'"; FAILED=1
fi

# 7c. set -euo pipefail.
if grep -q 'set -euo pipefail' "$SCRIPT"; then
  echo "  ok   7c set -euo pipefail present"
else
  echo "  FAIL 7c missing 'set -euo pipefail'"; FAILED=1
fi

if (( FAILED == 0 )); then
  echo "PASS resolve-spec tests"
  exit 0
else
  echo "FAIL resolve-spec tests"
  exit 1
fi
