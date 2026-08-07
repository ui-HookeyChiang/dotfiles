# Map: local tmux + nvim config drift

Status: open
Labels: wayfinder:map

## Destination

Decisions locked, implementation handed to flow-dev:
(1) a settled local+server two-layer tmux scheme (prefixes, passthrough, install.sh flags) written as agent-ready tickets; (2) root cause of nvim plugin/hotkey loss identified and the submodule-flow fix decided. Planning only — no implementation on this map.

## Notes

Domain: dotfiles installer + tmux/nvim submodules. HITL tickets use `grilling` and `domain-modeling` skills. User picked two-layer tmux with distinct prefixes (2026-08-07). tmux is already installed locally (/opt/homebrew/bin/tmux); the gap is configuration/nesting, not installation. nvim submodule observed detached at 6dd97f6 (origin/dev) while dotfiles records an older pointer — prime suspect for hotkey loss.

## Decisions so far

<!-- one line per closed ticket: [title](file) — gist -->

## Not yet specified

- What install.sh must change (flags? host-role detection? auto-start?) — sharpens after the tmux config spec ticket resolves.
- Whether nvim submodule should track a branch (dev vs master) and how install.sh should treat dirty/ahead submodules — sharpens after root-cause research resolves.

## Out of scope

- Implementing install.sh / tmux config / nvim submodule fixes — destination is decisions; implementation goes to flow-dev per ticket.

## Children

- [Research: tmux two-layer nesting options under oh-my-tmux](2026-08-07-research-tmux-nesting-options.md) — wayfinder:research, AFK, unblocked
- [Research: nvim hotkey-loss root cause timeline](2026-08-07-research-nvim-hotkey-loss-root-cause.md) — wayfinder:research, AFK, unblocked
- [Grilling: lock tmux local+server config spec](2026-08-07-grill-tmux-config-spec.md) — wayfinder:grilling, blocked by tmux research
- [Grilling: lock nvim submodule flow fix](2026-08-07-grill-nvim-submodule-flow.md) — wayfinder:grilling, blocked by nvim research
