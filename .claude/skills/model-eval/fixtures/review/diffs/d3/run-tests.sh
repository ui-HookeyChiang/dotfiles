#!/bin/sh
# Test suite — DO NOT MODIFY (forbidden file)
. "$(dirname "$0")/parse_worktree_path.sh"
pass=0; fail=0
chk() { # chk <desc> <expected> <actual> <expected_rc> <actual_rc>
  if [ "$2" = "$3" ] && [ "$4" = "$5" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL: $1 (expected [$2] rc=$4, got [$3] rc=$5)"; fi
}
r="$(wt_rel /repo /repo/.worktrees/foo)"; rc=$?
chk "t1 wt_rel simple" "foo" "$r" 0 $rc
r="$(wt_rel /repo /repo/src/foo)"; rc=$?
chk "t2 wt_rel outside" "" "$r" 1 $rc
r="$(wt_rel /repo /repo/.worktrees/ns/task-1)"; rc=$?
chk "t3 wt_rel nested" "ns/task-1" "$r" 0 $rc
r="$(wt_name foo)"; rc=$?
chk "t4 wt_name simple" "foo" "$r" 0 $rc
r="$(wt_name ns/task-1)"; rc=$?
chk "t5 wt_name nested" "ns" "$r" 0 $rc
r="$(wt_name "my wt/task 2")"; rc=$?
chk "t6 wt_name with space" "$r" "$r" 0 $rc
r="$(wt_task ns/task-1)"; rc=$?
chk "t7 wt_task simple" "" "$r" 0 $rc
r="$(wt_task "ns/task-1/deep")"; rc=$?
chk "t8 wt_task deep" "deep" "$r" 0 $rc
r="$(wt_task foo)"; rc=$?
chk "t9 wt_task absent" "" "$r" 0 $rc
r="$(wt_rel /repo /repo/.worktrees/a/b/c)"; rc=$?
chk "t10 wt_rel deep" "a/b/c" "$r" 0 $rc
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
