# tests/test-claude-hooks.sh points at a path that no longer exists

Status: needs-triage
Labels: test, ci

## Symptom

`bash tests/test-claude-hooks.sh` fails 5 of 9 assertions on `master`:

```
tests/test-claude-hooks.sh: line 101: /Users/hookeychiang/dotfiles/.claude/hooks/block-main-edit.sh: No such file or directory
not ok 9 - no file_path falls back to PWD (deny in main)
1..9
```

## Cause

The suite resolves the hook as `$repo_root/.claude/hooks/block-main-edit.sh`
(tests/test-claude-hooks.sh:25). Commit dbe50de ("refactor(install): drop
.claude intermediate symlink and teammate env (#146)") removed the `.claude`
compat symlink from the repo root, so nothing resolves under `.claude/` here
any more.

The hook itself was not deleted — it now lives at
`skill-dev/hooks/block-main-edit.sh`, and `~/.claude/hooks/block-main-edit.sh`
symlinks to it. Only the test's path is stale.

`.github/workflows/test.yml` has the same stale path in two steps:

- line 45, `bash -n (syntax check)`
- line 48, `shellcheck (bash files)`

## Scope

Both the test and the two CI steps need repointing, presumably to
`skill-dev/hooks/block-main-edit.sh`. Worth deciding during triage whether
this repo should test a hook owned by the submodule at all, or leave that to
skill-dev's own suite — repointing across the submodule boundary couples this
repo's tests to submodule internals.

## Notes

Found while declaring test stages (see docs/agents/test-stages.md); not fixed
there because that change was declaration-only. Every other suite passes: 61
assertions green across the remaining six.
