# Research: tmux two-layer nesting options under oh-my-tmux

Status: open
Labels: wayfinder:research
Map: 2026-08-07-wayfinder-tmux-nvim-map.md
Blocks: 2026-08-07-grill-tmux-config-spec.md

## Question

Local mac and remote servers will each run tmux (nested when ssh'd in). Under this repo's oh-my-tmux setup (.config/tmux submodule + .tmux.conf.local), what are the concrete options for: distinct inner/outer prefixes; passthrough toggle (e.g. F12 keys-off pattern); per-host (local vs server) conditional config from one shared dotfiles repo; and what install.sh would need to parameterize. Cite primary sources (oh-my-tmux docs, tmux man page).
