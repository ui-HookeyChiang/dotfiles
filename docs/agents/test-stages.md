# Test stages

Declared stages for this repo. A stage absent from this table is absent from
the repo — `flow` reports it SKIPPED rather than treating it as unwritten work.

| Stage | Command | Needs | Gate |
|---|---|---|---|
| lint | `make test-lint` | `shellcheck`, `bash` | `bash -n` and `shellcheck -S error` clean on the tracked shell entrypoints |
| integration | `make test-integration` | `zsh`, `bat`, `git`, bash 4+ (`brew install bash` on macOS) | every `tests/test-*.sh` exits 0 |

No unit stage: the shell here has no pure-function layer worth isolating —
`install.sh` is I/O against `$HOME`, and the suites already drive it through a
redirected `TARGET_HOME`. No e2e stage: the real target is a developer laptop,
so the integration suites' sandboxed `$HOME` is as close to real as this repo
gets without mutating the host.

## Run from the main checkout, not a linked worktree

`install.sh` refuses to run from a linked worktree, so `test-install-*.sh`
fail there with `refusing to install into real HOME from a linked worktree`.
That guard is the feature under test. Run `make test-integration` from
`/Users/hookeychiang/dotfiles` itself; `make` will stop with a diagnostic if
invoked from a worktree.

## Known red on master

`tests/test-claude-hooks.sh` fails 5 of 9 assertions: it invokes
`.claude/hooks/block-main-edit.sh`, a path that stopped resolving when commit
dbe50de dropped the `.claude` compat symlink. The hook still exists at
`skill-dev/hooks/block-main-edit.sh`; only the test's path is stale. CI has
the same gap in its `bash -n` and `shellcheck` steps. The suite is declared
here because it exists and runs; repointing it is
`docs/ticket/2026-08-09-test-claude-hooks-missing-hook.md`.
