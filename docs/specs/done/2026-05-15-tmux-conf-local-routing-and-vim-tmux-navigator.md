---
kind: spec
status: proposed
created: 2026-05-15
date: 2026-05-15
title: tmux conf.local routing fix + smart-splits tmux integration
slug: tmux-conf-local-routing-and-vim-tmux-navigator
---

# Design: tmux conf.local routing fix + vim-tmux-navigator integration

**Date:** 2026-05-15
**Status:** Proposed
**Owner:** hookey.chiang@ui.com
**Scope:** `~/dotfiles` + `~/.config/nvim` (two repos, see "Cross-repo coordination")

## Background

Two symptoms reported by user (2026-05-15):

1. **dotfiles `.tmux.conf.local` not taking effect** — clipboard / mouse / OSC52
   tweaks in `~/dotfiles/.tmux.conf.local` are not applied to running tmux
   sessions despite `install.sh` symlinking them to `$HOME`.
2. **`Ctrl+l` does not switch to the right pane** — user expects vim-tmux-navigator
   style cross-boundary navigation; current behavior is "clear screen".

### Root cause analysis

#### Symptom 1: oh-my-tmux overrides `$TMUX_CONF_LOCAL`

The oh-my-tmux upstream `.tmux.conf` (line containing `set-environment ...
TMUX_CONF_LOCAL`) forces `TMUX_CONF_LOCAL="$TMUX_CONF.local"` at tmux startup,
where `$TMUX_CONF` resolves to `~/.config/tmux/.tmux.conf` (the submodule path).
Therefore tmux always sources `~/.config/tmux/.tmux.conf.local` (the vanilla
19k template that ships with oh-my-tmux), regardless of any external
`TMUX_CONF_LOCAL` env var.

Evidence:

```
$ tmux display-message -p '#{TMUX_CONF_LOCAL}'
/home/hookey/.config/tmux/tmux.conf.local

$ echo $TMUX_CONF_LOCAL    # what .zshenv exports
/home/hookey/.tmux.conf.local
```

The `.zshenv:28` line `export TMUX_CONF_LOCAL="$HOME/.tmux.conf.local"` is
**dead code** — tmux ignores it.

`install.sh:54` lists `.tmux.conf.local` in the `DOTFILES` whitelist, which
symlinks it to `$HOME/.tmux.conf.local`. This file exists on disk but is
**never read by tmux**.

#### Symptom 2: oh-my-tmux binds `C-l` to clear-history

oh-my-tmux `.tmux.conf` contains:

```tmux
bind -n C-l send-keys C-l \; run 'sleep 0.2' \; clear-history
```

This is a root-table (`-n`, no prefix) binding that captures every `Ctrl+l`
keypress and routes it to shell clear + scrollback wipe. The user's
expectation is vim-tmux-navigator style: `Ctrl+l` should move to the right
tmux pane (or right vim split if inside vim/nvim).

The dotfiles `.tmux.conf.local` currently has no `C-h/j/k/l` overrides, so
even if it were being sourced, this binding would still leak through.

### Why these two symptoms are coupled

Fixing only symptom 2 (adding `bind -n C-l select-pane -R` to
`.tmux.conf.local`) wouldn't help, because tmux isn't reading that file.
The routing fix is a **prerequisite** for any future customization.

## Goals

1. Make `~/dotfiles/.tmux.conf.local` the **actual** file tmux sources for
   user overrides — so every existing setting (clipboard, mouse, OSC52) and
   every future addition takes effect.
2. Add vim-tmux-navigator-style `Ctrl+h/j/k/l` bindings that:
   - Inside vim/nvim: forward the key into the editor (vim plugin handles split nav)
   - Outside vim/nvim: directly `select-pane -L/D/U/R`
3. Install matching nvim plugin so the editor side cooperates.
4. Keep `install.sh` idempotent and CI-green on Ubuntu + macOS.

## Non-goals

- Touching `.vimrc` (user runs nvim primarily; vim side stays as-is).
- Forking oh-my-tmux or pinning to a custom branch.
- Adding `Ctrl+\\` "previous pane" binding (out of scope; can be added later).
- Touching scrollback / mouse-wheel-into-copy-mode behavior (user confirmed
  "目前沒事").

## Design

### Part A: Symlink topology change

#### Before

| Path | Target | Read by tmux? |
|------|--------|---------------|
| `~/.tmux.conf` | `~/.config/tmux/.tmux.conf` | yes (oh-my-tmux main) |
| `~/.tmux.conf.local` | `~/dotfiles/.tmux.conf.local` | **NO (dead symlink)** |
| `~/.config/tmux/.tmux.conf.local` | (regular file from oh-my-tmux submodule) | **yes (the wrong one)** |

#### After

| Path | Target | Read by tmux? |
|------|--------|---------------|
| `~/.tmux.conf` | `~/.config/tmux/.tmux.conf` | yes (unchanged) |
| `~/.config/tmux/.tmux.conf.local` | `~/dotfiles/.tmux.conf.local` | **yes (user overrides)** |
| `~/.tmux.conf.local` | (removed) | n/a |

### Part B: `install.sh` changes

Three concrete edits in `~/dotfiles/install.sh`:

1. **Remove `.tmux.conf.local` from `DOTFILES` array** (line 54).
2. **Add a new whitelist for "inside-submodule overrides"**, e.g. `SUBMODULE_OVERRIDES`:

   ```bash
   # File overrides that must live inside a submodule directory so the
   # submodule's own loader picks them up. Each entry is "src:dest" where
   # src is relative to $DOTFILES and dest is relative to $HOME.
   SUBMODULE_OVERRIDES=(
     ".tmux.conf.local:.config/tmux/.tmux.conf.local"
   )
   ```
3. **Add a loop** after the existing `link_one` calls that, for each entry:
   - Computes `src = $DOTFILES/<src>` and `dest = $HOME/<dest>`.
   - If `dest` is a regular file (i.e., the submodule's vanilla template),
     back it up to `$BACKUP_DIR` (reusing the existing backup machinery).
   - If `dest` is already a symlink (potentially to the right place or a
     stale one), `rm -f` it.
   - `ln -sf "$src" "$dest"`.
   - Verify with `[ "$(readlink -f "$dest")" = "$src" ]`.

4. **One-time cleanup**: after the loop, if `$HOME/.tmux.conf.local` exists
   AND is a symlink AND its target is inside `$DOTFILES`, remove it (it's the
   old dead symlink from the previous install layout). Skip if not a symlink
   or points elsewhere — be conservative.

5. **Submodule update interaction**: `install.sh` runs `git submodule update
   --init --recursive` before linking. After that, oh-my-tmux's working tree
   may contain a fresh `.tmux.conf.local` regular file. The new loop handles
   this correctly: backup → remove → symlink.

### Part C: `.tmux.conf.local` additions

Append to `~/dotfiles/.tmux.conf.local`:

```tmux
# -- vim-tmux-navigator -------------------------------------------------------
# Ctrl-h/j/k/l navigate splits in vim AND panes in tmux, seamlessly.
# When the current pane runs vim/nvim, forward the key into the editor so the
# vim-tmux-navigator plugin (or nvim-tmux-navigation) handles the move;
# otherwise tmux selects the adjacent pane directly.
#
# Detection: inspect the pane's foreground process via `ps -o state= -o comm=`
# and match against /(g?(view|n?vim?x?))(diff)?$/. Pattern is the standard
# vim-tmux-navigator regex (matches vim, nvim, view, vimdiff, gview, etc.).
# Uses POSIX grep -E (portable; rg unavailable inside if-shell on stock systems).
is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
bind-key -n C-h if-shell "$is_vim" 'send-keys C-h' 'select-pane -L'
bind-key -n C-j if-shell "$is_vim" 'send-keys C-j' 'select-pane -D'
bind-key -n C-k if-shell "$is_vim" 'send-keys C-k' 'select-pane -U'
bind-key -n C-l if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'

# Inside vim's copy-mode equivalents (tmux copy-mode-vi), also pass through.
bind-key -T copy-mode-vi C-h select-pane -L
bind-key -T copy-mode-vi C-j select-pane -D
bind-key -T copy-mode-vi C-k select-pane -U
bind-key -T copy-mode-vi C-l select-pane -R
```

Because `.tmux.conf.local` is sourced **after** oh-my-tmux's main conf, these
bindings override oh-my-tmux's `bind -n C-l send-keys C-l \; clear-history`.

### Part D: `.zshenv` cleanup

Remove line 28 of `~/dotfiles/.zshenv`:

```diff
-export TMUX_CONF_LOCAL="$HOME/.tmux.conf.local"
```

It's dead code (oh-my-tmux overrides it at tmux startup). Removing prevents
future maintainers from being misled into thinking the env var controls
oh-my-tmux behavior.

### Part E: nvim plugin (separate repo: `~/.config/nvim`)

User's nvim config is a LazyVim-style setup in `~/.config/nvim/lua/plugins/`.
Add a new file `lua/plugins/tmux-navigator.lua`:

```lua
return {
  "alexghergh/nvim-tmux-navigation",
  event = "VeryLazy",
  config = function()
    require("nvim-tmux-navigation").setup({
      disable_when_zoomed = true,
      keybindings = {
        left = "<C-h>",
        down = "<C-j>",
        up = "<C-k>",
        right = "<C-l>",
      },
    })
  end,
}
```

Why `alexghergh/nvim-tmux-navigation` over `christoomany/vim-tmux-navigator`:
- Lua-native (matches LazyVim ecosystem), no vimscript runtime overhead.
- Same key protocol (forwards `C-h/j/k/l` to tmux when at split edge), so
  tmux side is identical.
- Active maintenance (last commit < 6mo).

Trade-off: requires a separate PR/commit in the nvim repo. See
"Cross-repo coordination".

## Cross-repo coordination

Two independent repos:
- `~/dotfiles` (this repo) — symlink topology, tmux bindings, zshenv cleanup
- `~/.config/nvim` (separate repo) — nvim plugin spec

**Ordering**: tmux side works standalone (fallback `select-pane -L/R` triggers
when no vim detected). nvim side enhances behavior when editing. Land tmux
PR first; nvim PR can follow independently.

**Risk if nvim PR delayed**: zero. Without the nvim plugin, pressing `C-l`
inside nvim still works — tmux's `is_vim` check detects the running nvim
process and `send-keys C-l` into it. nvim receives `<C-l>` but, without the
plugin, treats it as the default redraw command. The user falls back to
nvim-native `<C-w>l` for window navigation until the plugin is installed.
Not broken, just not seamless.

## Testing & verification

### Automated (CI)

`.github/workflows/test.yml` already runs `install.sh` on ubuntu-22.04 +
macos-14. Add assertions after install:

```bash
test -L "$HOME/.config/tmux/.tmux.conf.local"
test "$(readlink -f "$HOME/.config/tmux/.tmux.conf.local")" = "$PWD/.tmux.conf.local"
test ! -e "$HOME/.tmux.conf.local"   # old symlink cleaned up
```

### Manual

After install on host:

```bash
# 1. tmux is sourcing the right file
tmux kill-server || true
tmux new-session -d
tmux display-message -p '#{TMUX_CONF_LOCAL}'
# expected: /home/hookey/.config/tmux/.tmux.conf.local
readlink -f "$HOME/.config/tmux/.tmux.conf.local"
# expected: /home/hookey/dotfiles/.tmux.conf.local

# 2. C-l binding is the new one
tmux list-keys -T root | grep ' C-l '
# expected: bind-key -T root C-l if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'
# NOT: bind-key -T root C-l send-keys C-l ...clear-history

# 3. Functional test (interactive)
# Open tmux, split pane horizontally: prefix + "
# Press Ctrl+l → cursor moves to right pane
# Open nvim in one pane, split vertically inside nvim
# Press Ctrl+l → moves between vim splits, then crosses into tmux pane
```

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| oh-my-tmux submodule update overwrites `~/.config/tmux/.tmux.conf.local` | High (every `git submodule update`) | `install.sh` is idempotent — re-run after submodule update restores symlink. Document in README. |
| User has uncommitted changes in `~/.config/tmux/.tmux.conf.local` (the regular file from oh-my-tmux) | Medium (first-time migration only) | `install.sh` backs up to `$BACKUP_DIR` before symlinking |
| `is_vim` regex false positive (e.g., shell process named `nvim-wrapper`) | Low | Standard vim-tmux-navigator pattern, battle-tested. Accept the edge case. |
| `is_vim` regex false negative on macOS (BSD `ps` column format differs) | Medium | Pattern includes `-o state= -o comm=` explicit format; tested on both. Verify in CI. |
| nvim PR not landed → `<C-l>` inside nvim hits default behavior | Low | Graceful: nvim redraws. User uses `<C-w>l` until plugin ships. |
| `bind -n` overrides oh-my-tmux's clear-history → user loses scrollback wipe shortcut | Medium | Document workaround: `prefix + Ctrl+l` (oh-my-tmux also binds this, prefix-protected). Add comment in `.tmux.conf.local`. |

## Out of scope (deferred)

- `Ctrl+\\` "go to previous pane" binding (vim-tmux-navigator standard).
- Toggle to disable smart navigation in specific panes.
- Documentation overhaul of README.md to explain the new override file location.

## Implementation order

1. **PR-1 (dotfiles)**: install.sh changes + `.tmux.conf.local` bindings + `.zshenv` cleanup + CI assertions.
   - One squashed commit; touches install.sh, .tmux.conf.local, .zshenv, .github/workflows/test.yml.
2. **PR-2 (nvim)**: add `lua/plugins/tmux-navigator.lua`.
   - Independent; can land before or after PR-1 with no coordination needed.

Both PRs follow `stacking-dev` workflow.
