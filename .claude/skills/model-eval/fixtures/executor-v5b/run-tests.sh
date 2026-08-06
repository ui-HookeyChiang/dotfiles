#!/bin/sh
# Test suite — DO NOT MODIFY (forbidden file)
D="$(dirname "$0")"
. "$D/queue-lib.sh"
pass=0; fail=0
chk() {
  if [ "$2" = "$3" ] && [ "$4" = "$5" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL: $1 (expected [$2] rc=$4, got [$3] rc=$5)"; fi
}

# --- task_make_id correctness ---
r="$(task_make_id "Deploy Build")"; rc=$?
chk "t1 simple normalize" "deploy-build" "$r" 0 $rc
r="$(task_make_id "Build__Deploy")"; rc=$?
chk "t2 collapse double hyphen" "build-deploy" "$r" 0 $rc
r="$(task_make_id " Deploy Task ")"; rc=$?
chk "t3 strip leading/trailing" "deploy-task" "$r" 0 $rc
r="$(task_make_id "___multi___")"; rc=$?
chk "t4 underscores collapse" "multi" "$r" 0 $rc

# --- idempotency (the unstated invariant the spec hints at) ---
r="$(task_make_id "$(task_make_id "Deploy Build")")"; rc=$?
chk "t5 idempotent simple" "deploy-build" "$r" 0 $rc
r="$(task_make_id "$(task_make_id "Build__Deploy")")"; rc=$?
chk "t6 idempotent double" "build-deploy" "$r" 0 $rc

# --- task_create uses normalized id ---
rec="$(task_create "Deploy Build" 3)"
r="$(task_get_id "$rec")"
chk "t7 create id normalized" "deploy-build" "$r" 0 0

# --- task_format output shape ---
rec="$(task_create "My Task" 2)"
r="$(task_format "$rec")"
case "$r" in *"[my-task]"*"My Task"*"critical"*"pending"*) r_ok=yes ;; *) r_ok=no ;; esac
chk "t8 format output" "yes" "$r_ok" 0 0

# --- task_set_status round-trip ---
rec="$(task_create "Job One" 5)"
rec2="$(task_set_status "$rec" "running")"
r="$(task_get_status "$rec2")"
chk "t9 set_status" "running" "$r" 0 0
r="$(task_get_id "$rec2")"
chk "t10 set_status preserves id" "job-one" "$r" 0 0

# --- task_priority_label ---
r="$(task_priority_label 1)"
chk "t11 priority critical" "critical" "$r" 0 0
r="$(task_priority_label 7)"
chk "t12 priority low" "low" "$r" 0 0

# --- task_status_valid ---
task_status_valid "pending"; rc=$?
chk "t13 status valid pending" "0" "$rc" 0 0
task_status_valid "bogus"; rc=$?
chk "t14 status invalid" "1" "$rc" 0 0

# --- runner CLI integration ---
r="$(sh "$D/task-runner.sh" banner | grep -c 'task-runner v1.0.0')"
chk "t15 banner" "1" "$r" 0 0
r="$(sh "$D/task-runner.sh" normalize "Hello World")"
chk "t16 CLI normalize" "hello-world" "$r" 0 0
sh "$D/task-runner.sh" idempotent "Build__Deploy" >/dev/null 2>&1; rc=$?
chk "t17 CLI idempotent" "0" "$rc" 0 0
r="$(sh "$D/task-runner.sh" priority 3)"
chk "t18 CLI priority" "high" "$r" 0 0
r="$(sh "$D/task-runner.sh" create "Build Deploy" 2 | head -1)"
chk "t19 CLI create id" "created: build-deploy" "$r" 0 0

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
