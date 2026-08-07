# Research: nvim hotkey loss — root cause

Ticket: docs/ticket/2026-08-07-research-nvim-hotkey-loss-root-cause.md (branch wayfinder-tmux-nvim-map)
Date: 2026-08-07. All evidence from local git (read-only) against the main checkout.

## Verdict

**Hypothesis CONFIRMED**, with one adjacent second mechanism.

The `.config/nvim` submodule working tree sits on `origin/dev` tip
`6dd97f6` ("feat: add `<Leader>fw` for grep_cword"), but the dotfiles
superproject still records `10b3028` (verified: `git ls-tree HEAD
.config/nvim` → `160000 commit 10b3028…`). Any `git submodule update`
— which `install.sh` runs unconditionally in `init_submodules()`
(install.sh:574, `git -C "$REPO_ROOT" submodule update --init
--recursive`) — checks the submodule back out to the recorded
`10b3028`, silently dropping the two hotkey commits from the working
tree:

```
10b3028..6dd97f6:
  6dd97f6 feat: add <Leader>fw for grep_cword (find word)
  5bc6ae7 fix: guard nightly-only features (vim.pack, PackChanged, fillchars trunc)
```

That is exactly the "hotkeys disappear" symptom: `<Leader>fw` and the
nightly-feature guards vanish, and `git status` in the superproject
shows the `+` (new-commits) drift for `.config/nvim` until the next
reset re-hides it.

## Timeline (from submodule reflog + superproject log)

| When (local) | Event | Evidence |
|---|---|---|
| 2026-06-17 | Superproject bumps pointer to `10b3028` ("merged dev", nvim PR #4) — **last bump ever** | dotfiles commit `263bbe3` |
| 2026-06-27 22:21 | Submodule checked out detached at `10b3028` | reflog `checkout: moving from 82bd27a… to 10b3028…` |
| 2026-07-03 12:16–12:17 | Branch `feat/bootstrap-tooling` created; commit `44a0cef` (Makefile + Dockerfile) | reflog |
| 2026-07-09 17:54 | **Backward move**: `checkout: moving from feat/bootstrap-tooling to 10b3028…` — the signature of a `git submodule update` reset; `44a0cef` work disappeared from the working tree | reflog |
| 2026-07-20 13:36–16:50 | While detached: `100f8a3` → amended to `5bc6ae7`, then `6dd97f6` (`<Leader>fw`) | reflog |
| since 2026-07-20 | HEAD parked detached at `6dd97f6`; pointer never bumped, so every future `submodule update` will re-lose it | `git branch -v`, `git ls-tree` |
| 2026-08-06 | Separate incident: test install from a linked worktree repointed home symlinks at a disposable checkout; zshrc/nvim broke. Guard added. | install.sh:33–36 comment; commit `f654bba` |

## Mechanism (confirmed)

1. Development happens inside `~/dotfiles/.config/nvim` on detached
   HEAD / topic branches; commits are pushed to the nvim repo's
   `origin/dev` (verified: `6dd97f6` is `origin/dev` tip, so the two
   hotkey commits **are pushed — no data loss, only working-tree
   loss**).
2. The superproject pointer is only bumped by an explicit
   `chore(nvim): bump submodule` commit; the last one was 2026-06-17
   (`263bbe3` → `10b3028`).
3. `install.sh` `init_submodules()` (install.sh:568–574) runs
   `git submodule update --init --recursive` with no branch tracking
   (`.gitmodules` sets `branch = dev` for `.config/nvim`, but plain
   `submodule update` ignores `branch` unless `--remote` is given) →
   checkout of stale `10b3028` → hotkeys gone. The 2026-07-09 reflog
   entry is a recorded occurrence of exactly this reset.

## Refuted / ruled out

- Data loss at the git object level: no — lost commits stayed in the
  submodule reflog and are on `origin/dev`.
- install.sh deleting the nvim directory: no such path; the 2026-08-06
  incident was symlink repointing from a worktree install (now blocked
  by `guard_canonical_root`), not directory deletion by the submodule
  code.

## Residual risks noted

- `44a0cef` (Makefile/Dockerfile) exists **only** on local branch
  `feat/bootstrap-tooling` — on no remote branch. Unpushed; will be
  lost if the local clone is discarded.
- Local `dev` branch is stale (`ahead 34, behind 308` vs `origin/dev`
  after old rebases) — misleading; local work is done detached instead.

## Fix directions (for follow-up ticket, not implemented here)

1. Bump the superproject pointer to `6dd97f6` (routine after every
   nvim change), and/or
2. Make `init_submodules` refuse to move a submodule whose HEAD is
   ahead of / diverged from the recorded pointer (dirty/drift guard),
   or use `submodule update --remote` for `.config/nvim` given
   `.gitmodules` already declares `branch = dev`.
3. Push `feat/bootstrap-tooling` (`44a0cef`).
