# Grilling: lock nvim submodule flow fix

Status: done
Labels: wayfinder:grilling
Map: 2026-08-07-wayfinder-tmux-nvim-map.md
Blocked-by: 2026-08-07-research-nvim-hotkey-loss-root-cause.md

## Question

Given the confirmed root cause, decide with the user: branch strategy for the nvim submodule (track dev vs merge to master), pointer-bump discipline, and how install.sh should treat dirty/ahead submodules (guard vs auto-stash vs refuse). Output: decision recorded here + agent-ready implementation ticket(s) for flow-dev.

## Resolution (2026-08-07)

Decided (c) hybrid: generic install.sh drift guard (warn + skip resetting any submodule whose HEAD has commits not contained in the recorded pointer; applies to .config/nvim AND .config/tmux) plus pointer-bump discipline. Immediate bump of .config/nvim pointer to 6dd97f6 included in the implementation PR. Push unpushed nvim branch feat/bootstrap-tooling (44a0cef). Local stale nvim `dev` branch: salvage-worthy commits cherry-picked to a PR against nvim dev (in flight, branch salvage/dev-ahead-34), then reset local dev to origin/dev. Future nvim work happens on topic branches off origin/dev, not detached. Implementation ticket: 2026-08-07-impl-nvim-submodule-guard.md.
