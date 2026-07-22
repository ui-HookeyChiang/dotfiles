#!/bin/bash
# md2adf-test.sh — smoke tests for md2adf.py covering all node types.
set -euo pipefail
SCRIPT=/home/hookey/.claude/skills/jira/scripts/md2adf.py
fail=0

assert_count() {
    local name=$1 expected=$2 actual=$3
    if [ "$actual" -ne "$expected" ]; then
        echo "FAIL: $name expected $expected, got $actual"
        fail=$((fail+1))
    else
        echo "PASS: $name = $expected"
    fi
}

# --- Test 1: heading levels ---
out=$(printf '## H2\n### H3\n#### H4\n' | python3 "$SCRIPT")
assert_count "H2 count" 1 "$(echo "$out" | jq '[.content[] | select(.type=="heading" and .attrs.level==2)] | length')"
assert_count "H3 count" 1 "$(echo "$out" | jq '[.content[] | select(.type=="heading" and .attrs.level==3)] | length')"
assert_count "H4 count" 1 "$(echo "$out" | jq '[.content[] | select(.type=="heading" and .attrs.level==4)] | length')"

# --- Test 2: codeBlock with language ---
out=$(printf '```bash\nls -la\n```\n' | python3 "$SCRIPT")
assert_count "codeBlock count" 1 "$(echo "$out" | jq '[.content[] | select(.type=="codeBlock")] | length')"
lang=$(echo "$out" | jq -r '.content[0].attrs.language // "NONE"')
[ "$lang" = "bash" ] && echo "PASS: language=bash" || { echo "FAIL: language=$lang"; fail=$((fail+1)); }
text=$(echo "$out" | jq -r '.content[0].content[0].text')
[ "$text" = "ls -la" ] && echo "PASS: codeBlock text" || { echo "FAIL: codeBlock text='$text'"; fail=$((fail+1)); }

# --- Test 3: bullet list ---
out=$(printf -- '- one\n- two\n- three\n' | python3 "$SCRIPT")
assert_count "bulletList count" 1 "$(echo "$out" | jq '[.content[] | select(.type=="bulletList")] | length')"
assert_count "bullet items" 3 "$(echo "$out" | jq '.content[0].content | length')"

# --- Test 4: ordered list ---
out=$(printf '1. first\n2. second\n3. third\n' | python3 "$SCRIPT")
assert_count "orderedList count" 1 "$(echo "$out" | jq '[.content[] | select(.type=="orderedList")] | length')"
assert_count "ordered items" 3 "$(echo "$out" | jq '.content[0].content | length')"

# --- Test 5: table with header ---
out=$(printf '| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n' | python3 "$SCRIPT")
assert_count "table count" 1 "$(echo "$out" | jq '[.content[] | select(.type=="table")] | length')"
assert_count "table rows" 3 "$(echo "$out" | jq '.content[0].content | length')"
header_type=$(echo "$out" | jq -r '.content[0].content[0].content[0].type')
[ "$header_type" = "tableHeader" ] && echo "PASS: first row is tableHeader" || { echo "FAIL: first row type=$header_type"; fail=$((fail+1)); }

# --- Test 6: inline code mark ---
out=$(printf 'Run `make test` to verify.\n' | python3 "$SCRIPT")
mark=$(echo "$out" | jq -r '.content[0].content[1].marks[0].type')
[ "$mark" = "code" ] && echo "PASS: inline code mark" || { echo "FAIL: inline code mark=$mark"; fail=$((fail+1)); }
text=$(echo "$out" | jq -r '.content[0].content[1].text')
[ "$text" = "make test" ] && echo "PASS: inline code text" || { echo "FAIL: inline code text='$text'"; fail=$((fail+1)); }

# --- Test 7: bold mark ---
out=$(printf 'This is **important** stuff.\n' | python3 "$SCRIPT")
mark=$(echo "$out" | jq -r '.content[0].content[1].marks[0].type')
[ "$mark" = "strong" ] && echo "PASS: strong mark" || { echo "FAIL: strong mark=$mark"; fail=$((fail+1)); }

# --- Test 8: top-level structure ---
out=$(printf '# H1\n' | python3 "$SCRIPT")
[ "$(echo "$out" | jq -r '.type')" = "doc" ] && echo "PASS: top type=doc" || { echo "FAIL: top type"; fail=$((fail+1)); }
[ "$(echo "$out" | jq -r '.version')" = "1" ] && echo "PASS: version=1" || { echo "FAIL: version"; fail=$((fail+1)); }

# === Darwin-review follow-ups: edge cases the original 18 missed ===

# --- Test 9: empty input -> empty doc envelope ---
out=$(printf '' | python3 "$SCRIPT")
assert_count "empty input -> 0 children" 0 "$(echo "$out" | jq '.content | length')"

# --- Test 10: nested bullet (depth 2) ---
out=$(printf -- '- a\n  - a1\n  - a2\n- b\n' | python3 "$SCRIPT")
assert_count "outer bullet items" 2 "$(echo "$out" | jq '.content[0].content | length')"
nested_count=$(echo "$out" | jq '[.content[0].content[0].content[] | select(.type=="bulletList")] | length')
assert_count "nested bulletList present" 1 "$nested_count"
assert_count "nested items=2" 2 "$(echo "$out" | jq '.content[0].content[0].content[1].content | length')"

# --- Test 11: bold containing inline code (Darwin Bug #2 fix) ---
out=$(printf 'Run **run `make`** now.\n' | python3 "$SCRIPT")
strong_with_code=$(echo "$out" | jq '[.content[0].content[] | select((.marks // []) | map(.type) | sort == ["code","strong"])] | length')
assert_count "bold+code composite mark" 1 "$strong_with_code"

# --- Test 12: unclosed code fence emits stderr warning ---
warn=$(printf '%s%s%sbash\necho hi\nno close\n' '`' '`' '`' | python3 "$SCRIPT" 2>&1 >/dev/null)
case "$warn" in
    *"unclosed code fence"*) echo "PASS: unclosed fence warning" ;;
    *) echo "FAIL: unclosed fence — got: $warn"; fail=$((fail+1)) ;;
esac
out=$(printf '%s%s%sbash\necho hi\nno close\n' '`' '`' '`' | python3 "$SCRIPT" 2>/dev/null)
assert_count "unclosed-fence still emits codeBlock" 1 \
    "$(echo "$out" | jq '[.content[] | select(.type=="codeBlock")] | length')"

# --- Test 13: table without alignment row warns + falls back to paragraph ---
warn=$(printf '| a | b |\n| 1 | 2 |\n' | python3 "$SCRIPT" 2>&1 >/dev/null)
case "$warn" in
    *"alignment"*) echo "PASS: table-without-alignment warning" ;;
    *) echo "FAIL: table-no-align — got: $warn"; fail=$((fail+1)) ;;
esac
out=$(printf '| a | b |\n| 1 | 2 |\n' | python3 "$SCRIPT" 2>/dev/null)
assert_count "table-no-align emits 0 tables" 0 \
    "$(echo "$out" | jq '[.content[] | select(.type=="table")] | length')"

# --- Test 14: paragraph after a list does NOT eat next paragraph ---
out=$(printf -- '- one\n- two\n\nA paragraph after.\n' | python3 "$SCRIPT")
assert_count "list + paragraph: 2 top nodes" 2 "$(echo "$out" | jq '.content | length')"
assert_count "second node is paragraph" 1 \
    "$(echo "$out" | jq '[.content[1] | select(.type=="paragraph")] | length')"

# --- Summary ---
echo ""
if [ $fail -eq 0 ]; then
    echo "SUMMARY: ALL TESTS PASS"
    exit 0
else
    echo "SUMMARY: $fail failures"
    exit 1
fi
