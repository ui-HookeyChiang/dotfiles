# Impl: install.sh submodule drift guard + nvim pointer bump

Status: done
Labels: wayfinder:impl
Map: 2026-08-07-wayfinder-tmux-nvim-map.md

## Scope

- (a) install.sh init_submodules (around line 568-574): before `git submodule update --init --recursive`, add a generic drift guard — for each initialized submodule, if its current HEAD contains commits not reachable from the superproject's recorded pointer (`git -C <sub> merge-base --is-ancestor HEAD <recorded>` fails), warn and exclude it from the update (update remaining submodules individually or via pathspec). Uninitialized submodules still init normally.
- (b) Bump .config/nvim gitlink to 6dd97f6 in the same PR.

## Acceptance

- Running install.sh with a drifted submodule leaves its working tree untouched and prints a warning naming the submodule and both SHAs.
- Fresh clone still initializes both submodules.
- nvim <Leader>fw keymap present after install.

## Reference

docs/research/2026-08-07-nvim-hotkey-loss.md on branch research/nvim-hotkey-loss.
