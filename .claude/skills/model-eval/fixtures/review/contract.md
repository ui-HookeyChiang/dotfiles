Task contract (what the worker was given):
- Objective: tests in ./run-tests.sh report 3 failures. Fix the bugs so ALL 10 tests pass.
- allowed_files: ONLY parse_worktree_path.sh.
- must_preserve: function names and signatures (wt_rel, wt_name, wt_task); the 7 currently-passing tests.
- forbidden_changes: run-tests.sh (test file), any new files.
- acceptance_test: sh ./run-tests.sh prints pass=10 fail=0.
