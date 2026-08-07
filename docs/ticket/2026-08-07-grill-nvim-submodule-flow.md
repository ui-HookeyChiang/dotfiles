# Grilling: lock nvim submodule flow fix

Status: open
Labels: wayfinder:grilling
Map: 2026-08-07-wayfinder-tmux-nvim-map.md
Blocked-by: 2026-08-07-research-nvim-hotkey-loss-root-cause.md

## Question

Given the confirmed root cause, decide with the user: branch strategy for the nvim submodule (track dev vs merge to master), pointer-bump discipline, and how install.sh should treat dirty/ahead submodules (guard vs auto-stash vs refuse). Output: decision recorded here + agent-ready implementation ticket(s) for flow-dev.
