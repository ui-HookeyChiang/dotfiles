# Grilling: lock tmux local+server config spec

Status: done
Labels: wayfinder:grilling
Map: 2026-08-07-wayfinder-tmux-nvim-map.md
Blocked-by: 2026-08-07-research-tmux-nesting-options.md

## Question

Given the researched options, decide with the user: exact outer/inner prefixes, passthrough mechanism, how local vs server hosts are distinguished, and the agent-ready scope of install.sh changes. Output: decision recorded here + agent-ready implementation ticket(s) for flow-dev.

## Resolution (2026-08-07)

Decided Option A (F12 keys-off toggle on outer tmux, gated `if-shell '[ -z "$SSH_CONNECTION" ]'`) combined with Option C (double-tap `bind C-b send-prefix` fallback). Keep F12 as the toggle key. Add OFF indicator via `tmux_conf_theme_status_right` format `#{?#{==:#{client_key_table},off},OFF,}`. Auto-start/auto-attach explicitly out of scope (future ticket). Delivery = single PR editing only repo-root `.tmux.conf.local`; install.sh untouched. Implementation ticket: 2026-08-07-impl-tmux-nesting-config.md.
