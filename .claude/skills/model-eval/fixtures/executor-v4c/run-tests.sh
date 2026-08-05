#!/bin/sh
# Test suite — DO NOT MODIFY (forbidden file)
D="$(dirname "$0")"
pass=0; fail=0
chk() {
  if [ "$2" = "$3" ] && [ "$4" = "$5" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL: $1 (expected [$2] rc=$4, got [$3] rc=$5)"; fi
}
src() { . "$D/tool.sh" 2>/dev/null; }
r="$( (src; command -v agent_compat_root >/dev/null && echo yes) )"; rc=$?
chk "t1 agent_compat_root defined" "yes" "$r" 0 $rc
r="$( (src; agent_compat_normalize "Foo_Bar") 2>/dev/null )"; rc=$?
chk "t2 normalize kebab" "foo-bar" "$r" 0 $rc
r="$( (src; AGENT_COMPAT_ROOT=/x agent_compat_root) 2>/dev/null )"; rc=$?
chk "t3 env override root" "/x" "$r" 0 $rc
r="$( (src; agent_compat_root | grep -c '\.config/agent-compat$') 2>/dev/null )"; rc=$?
chk "t4 default root path" "1" "$r" 0 $rc
(src; AGENT_COMPAT_STRICT=1 agent_compat_strict) 2>/dev/null; rc=$?
chk "t5 strict on" "0" "$rc" 0 0
(src; AGENT_COMPAT_STRICT=0 agent_compat_strict) 2>/dev/null; rc=$?
chk "t6 strict off" "1" "$rc" 0 0
r="$( (src; [ -n "$AGENT_COMPAT_VERSION" ] && echo set) )"; rc=$?
chk "t7 version var set" "set" "$r" 0 $rc
r="$( (src; compat_report | grep -c '^agent-compat v1\.4\.0 ') 2>/dev/null )"; rc=$?
chk "t8 report banner" "1" "$r" 0 $rc
r="$( (src; AGENT_COMPAT_ROOT=/tmp/x compat_report | grep -c 'root=/tmp/x$') 2>/dev/null )"; rc=$?
chk "t9 report shows root" "1" "$r" 0 $rc
r="$( (src; AGENT_COMPAT_STRICT=1 compat_check Foo_Bar) 2>/dev/null )"; rc=$?
chk "t10 strict check line" "agent-compat: strict check foo-bar" "$r" 0 $rc
r="$( (src; compat_check Foo_Bar) 2>/dev/null )"; rc=$?
chk "t11 check line" "agent-compat: check foo-bar" "$r" 0 $rc
r="$(grep -ci 'parity' "$D/helpers.sh")"
chk "t12 no parity leftovers in helpers.sh" "0" "$r" 0 0
r="$(grep -ci 'parity' "$D/tool.sh")"
chk "t13 no parity leftovers in tool.sh" "0" "$r" 0 0
r="$( (src; command -v agent_parity_root >/dev/null 2>&1 && echo old || echo gone) )"; rc=$?
chk "t14 old function absent" "gone" "$r" 0 $rc
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
