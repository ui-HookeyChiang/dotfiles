# tests

Integration tests for this dotfiles repo.

## test-zsh-init.sh

TAP-13 integration test for zsh init behavior. Verifies that `EDITOR`,
`PATH`, `DEBEMAIL`, and aliases propagate correctly across all zsh
invocation modes — the regression class fixed by PR-9 (`.zshenv`).

### Run

```bash
# Default: test the repo's dotfiles via ZDOTDIR override (works
# regardless of whether `bash install.sh` has been run on this host).
./tests/test-zsh-init.sh

# Alternatively: test the user's installed dotfiles via $HOME.
# Skips with TAP `1..0 # SKIP` if dotfiles are not deployed.
./tests/test-zsh-init.sh --installed
```

Exit code is the number of failed tests (0 on full pass).

### What is tested

| # | Assertion |
|---|-----------|
| T1 | `zsh -c 'echo $EDITOR'` outputs `nvim` (non-login non-interactive) |
| T2 | `zsh -ic 'echo $EDITOR'` outputs `nvim` (interactive non-login) |
| T3 | `zsh -lic 'echo $EDITOR'` outputs `nvim` (login interactive) |
| T4 | `$PATH` contains `$HOME/.local/bin` |
| T5 | `bat` (or `batcat`) is resolvable in non-login zsh |
| T6 | login zsh exits 0 on Linux (`mesg` tty-guard works) |
| T7 | non-tty zsh reaches end despite `mesg` failure |
| T8 | interactive zsh defines `alias v=$EDITOR` |
| T9 | `$HOME/.local/bin` precedes `/usr/bin` in `$PATH` |
| T10 | warm `zsh -lic 'exit'` runs in under 1.5s |
