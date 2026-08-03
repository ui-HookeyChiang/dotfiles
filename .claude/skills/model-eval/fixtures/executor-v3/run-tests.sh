#!/bin/sh
# Test suite — DO NOT MODIFY (forbidden file)
. "$(dirname "$0")/parse_worktree_path.sh"
pass=0; fail=0
chk() {
  if [ "$2" = "$3" ] && [ "$4" = "$5" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL: $1 (expected [$2] rc=$4, got [$3] rc=$5)"; fi
}
r="$(wt_rel /repo /repo/.worktrees/foo)"; rc=$?
chk "t1 wt_rel simple" "foo" "$r" 0 $rc
r="$(wt_rel /repo /repo/src/foo)"; rc=$?
chk "t2 wt_rel outside" "" "$r" 1 $rc
r="$(wt_rel /repo /repo/.worktrees/ns/task-1)"; rc=$?
chk "t3 wt_rel nested" "ns/task-1" "$r" 0 $rc
r="$(wt_name ns/task-1)"; rc=$?
chk "t4 wt_name nested" "ns" "$r" 0 $rc
r="$(wt_name "my wt/task 2")"; rc=$?
chk "t5 wt_name space" "my wt" "$r" 0 $rc
r="$(wt_task ns/task-1)"; rc=$?
chk "t6 wt_task simple" "task-1" "$r" 0 $rc
r="$(wt_task "ns/task-1/deep")"; rc=$?
chk "t7 wt_task deep" "task-1" "$r" 0 $rc
r="$(wt_task foo)"; rc=$?
chk "t8 wt_task absent" "" "$r" 0 $rc
r="$(wt_depth "")"; rc=$?
chk "t9 wt_depth empty" "0" "$r" 0 $rc
r="$(wt_depth a/b/c)"; rc=$?
chk "t10 wt_depth 3" "3" "$r" 0 $rc
r="$(wt_depth "my wt/x")"; rc=$?
chk "t11 wt_depth space" "2" "$r" 0 $rc
r="$(wt_id /repo /repo/.worktrees/ns/task-1)"; rc=$?
chk "t12 wt_id nested" "ns:task-1" "$r" 0 $rc
r="$(wt_id /repo /repo/.worktrees/solo)"; rc=$?
chk "t13 wt_id top-level" "solo" "$r" 0 $rc
r="$(wt_id /repo /repo/etc/passwd)"; rc=$?
chk "t14 wt_id outside" "" "$r" 1 $rc
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
