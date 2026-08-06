#!/bin/sh
# Test suite — DO NOT MODIFY (forbidden file)
D="$(dirname "$0")"
pass=0; fail=0
chk() {
  if [ "$2" = "$3" ] && [ "$4" = "$5" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL: $1 (expected [$2] rc=$4, got [$3] rc=$5)"; fi
}
# t1: make check succeeds (lint passes)
r="$(cd "$D" && make check 2>&1 | grep -c 'check: passed')"; rc=$?
chk "t1 make-check passes" "1" "$r" 0 $rc
# t2: make build succeeds
r="$(cd "$D" && make clean >/dev/null 2>&1; make build 2>&1 | grep -c 'build: done')"; rc=$?
chk "t2 make-build completes" "1" "$r" 0 $rc
# t3: config copied to dist
r="$(cd "$D" && [ -f dist/config.yml ] && echo yes || echo no)"; rc=$?
chk "t3 config in dist" "yes" "$r" 0 $rc
# t4: lint-check catches missing key in a bad file
bad="$(mktemp)"
printf 'name: x\n' > "$bad"
sh "$D/lint-check.sh" "$bad" >/dev/null 2>&1; rc=$?
rm -f "$bad"
chk "t4 lint catches missing keys" "1" "$rc" 0 0
# t5: lint-check passes on a complete file
good="$(mktemp)"
printf 'name: x\nversion: 1\nhost: h\nport: 1\ntimeout: 5\nretry_limit: 1\n' > "$good"
sh "$D/lint-check.sh" "$good" >/dev/null 2>&1; rc=$?
rm -f "$good"
chk "t5 lint passes complete file" "0" "$rc" 0 0
# t6: lint-check rejects tabs
tab="$(mktemp)"
printf 'name: x\nversion: 1\nhost: h\nport: 1\ntimeout: 5\nretry_limit: 1\n\tindented: bad\n' > "$tab"
sh "$D/lint-check.sh" "$tab" >/dev/null 2>&1; rc=$?
rm -f "$tab"
chk "t6 lint rejects tabs" "1" "$rc" 0 0
# t7: lint-check is executable
r="$([ -f "$D/lint-check.sh" ] && echo yes || echo no)"
chk "t7 lint-check exists" "yes" "$r" 0 0
# t8: Makefile check target invokes lint-check
r="$(cd "$D" && grep -c 'lint-check' Makefile)"
chk "t8 Makefile wires lint-check" "1" "$r" 0 0
cd "$D" && make clean >/dev/null 2>&1
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
