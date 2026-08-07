# Research: nvim hotkey-loss root cause timeline

Status: done
Labels: wayfinder:research
Map: 2026-08-07-wayfinder-tmux-nvim-map.md
Blocks: 2026-08-07-grill-nvim-submodule-flow.md

## Question

User repeatedly loses nvim plugin changes (e.g. hotkeys) — cause unknown. Hypothesis: .config/nvim submodule sits on origin/dev commits (currently 6dd97f6) while the dotfiles superproject records an older pointer; install.sh or `git submodule update` resets it. Reconstruct the timeline from the nvim submodule reflog, dotfiles history of the submodule pointer, and install.sh's submodule-handling code (including the 2026-08-06 incident comment near install.sh:36). Confirm or refute the hypothesis; identify every code path that can move the submodule HEAD.

## Resolution

Findings on branch `research/nvim-hotkey-loss`, file docs/research/2026-08-07-nvim-hotkey-loss.md.
