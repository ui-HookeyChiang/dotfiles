# Impl: tmux nesting config — F12 keys-off toggle + double-tap fallback

Status: ready-for-agent
Labels: wayfinder:impl
Map: 2026-08-07-wayfinder-tmux-nvim-map.md

## Scope

Edit repo-root `.tmux.conf.local` only.

- (a) F12 off-table block on outer only, wrapped in `if-shell '[ -z "$SSH_CONNECTION" ]'`:
  - `bind -T root F12` — set prefix None, set key-table off, refresh-client -S
  - `bind -T off F12` — set -u prefix, set -u key-table, refresh-client -S
- (b) `bind C-b send-prefix` double-tap fallback (unconditional).
- (c) OFF indicator appended to `tmux_conf_theme_status_right`.

## Acceptance

- On local mac, after F12 the keys C-b and C-h/j/k/l reach the inner (ssh) tmux; F12 again restores.
- Server-side tmux behavior unchanged.
- `tmux source-file` reloads without errors on both.

## Forbidden

- install.sh
- .config/tmux submodule

## Reference

docs/research/2026-08-07-tmux-nesting-options.md on branch research/tmux-nesting-options.
