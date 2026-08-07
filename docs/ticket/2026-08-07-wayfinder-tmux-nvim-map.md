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

- [Research: tmux two-layer nesting options under oh-my-tmux](2026-08-07-research-tmux-nesting-options.md) — options researched; A (F12 keys-off) + C (double-tap send-prefix) picked.
- [Research: nvim hotkey-loss root cause timeline](2026-08-07-research-nvim-hotkey-loss-root-cause.md) — root cause confirmed: stale pointer + unconditional submodule update.
- [Grilling: lock tmux local+server config spec](2026-08-07-grill-tmux-config-spec.md) — spec locked: F12 toggle gated on no SSH_CONNECTION, double-tap fallback, OFF indicator; .tmux.conf.local only.
- [Grilling: lock nvim submodule flow fix](2026-08-07-grill-nvim-submodule-flow.md) — flow locked: generic drift guard + pointer bump to 6dd97f6 + salvage of stale dev branch.

## Not yet specified

(none — both items sharpened into the impl tickets below)

## Out of scope

- Implementing install.sh / tmux config / nvim submodule fixes — destination is decisions; implementation goes to flow-dev per ticket.
- Note: implementation tickets are now charted and the map's route is fully clear — destination reached pending the impl handoff to flow-dev.

## Children

- [Research: tmux two-layer nesting options under oh-my-tmux](2026-08-07-research-tmux-nesting-options.md) — wayfinder:research, closed
- [Research: nvim hotkey-loss root cause timeline](2026-08-07-research-nvim-hotkey-loss-root-cause.md) — wayfinder:research, closed
- [Grilling: lock tmux local+server config spec](2026-08-07-grill-tmux-config-spec.md) — wayfinder:grilling, closed
- [Grilling: lock nvim submodule flow fix](2026-08-07-grill-nvim-submodule-flow.md) — wayfinder:grilling, closed
- [Impl: tmux nesting config — F12 keys-off toggle + double-tap fallback](2026-08-07-impl-tmux-nesting-config.md) — wayfinder:impl, unblocked, ready-for-agent, HITL not required
- [Impl: install.sh submodule drift guard + nvim pointer bump](2026-08-07-impl-nvim-submodule-guard.md) — wayfinder:impl, unblocked, ready-for-agent, HITL not required
