# flow-dev integration tests

This directory holds Feature Integration cross-task integration suites — end-to-end
flows that exercise the contract surface between multiple stacked PRs
inside a single feature. Each subdirectory is a self-contained driver
(`test.sh`) that builds tmpdir fixtures, runs the real PR1/PR2/PR3/PR4
deliverables, asserts cross-task invariants, and cleans up on exit.
These suites are permanent regression coverage per
`flow-dev/SKILL.md` Feature Integration, not throwaway eval artifacts.

Run a suite directly:

```bash
bash flow-dev/scripts/tests/integration/<suite>/test.sh
```

Each driver exits 0 on all-pass, 1 on any failure, and prints an
`N/M PASS` summary at the bottom. Drivers require `python3`, `jq`,
`git`, and (for `adopt-superpowers-plan-e2e`) the PR1 parser plus
the PR2 `docs-lifecycle.py from-brainstorming` subcommand to be on disk.
