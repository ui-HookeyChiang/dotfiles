---
kind: spec
status: done
created: 2026-09-02
date: 2026-09-02
title: tmux powerline font SOP (MesloLGS NF)
slug: tmux-powerline-font-sop
---

# SOP: tmux status bar shows `?` instead of powerline arrows

**Date:** 2026-09-02  
**Status:** Done  
**Scope:** macOS terminal + tmux (oh-my-tmux + p10k)

## Symptom

After PR #159, the tmux status bar and window list show **question marks** where
powerline separator arrows should appear. p10k may look fine in some tabs but tmux
does not.

## Root cause

`.tmux.conf.local` configures oh-my-tmux powerline separators using Private Use
Area code points (`U+E0B0`–`U+E0B3`). Those glyphs exist only in **Nerd Font /
Powerline-patched** fonts (MesloLGS NF matches p10k's `POWERLEVEL9K_MODE=powerline`).

If the terminal profile uses an unpatched font (e.g. **Monaco**, **Menlo**), macOS
renders missing glyphs as `?`.

This is **not** a tmux config bug.

## Automated fix (preferred)

Re-run the dotfiles installer on macOS — core install now:

1. Downloads MesloLGS NF (Regular/Bold/Italic/Bold Italic) to `~/Library/Fonts/`
2. Updates iTerm2 default profile font when it is still on an unpatched font

```bash
cd ~/dotfiles && ./install.sh
```

Open a **new iTerm tab or window** (existing tabs keep the old font until recreated).

## Manual fix

### 1. Install MesloLGS NF

```bash
mkdir -p ~/Library/Fonts
base='https://github.com/romkatv/powerlevel10k-media/raw/master'
for variant in Regular Bold Italic 'Bold Italic'; do
  curl -fsSL "$base/MesloLGS%20NF%20${variant// /%20}.ttf" \
    -o "$HOME/Library/Fonts/MesloLGS NF ${variant}.ttf"
done
```

### 2. Set terminal font

**iTerm2:** Settings → Profiles → Text → Font → **MesloLGS NF** (14pt recommended).

**Other terminals:** pick any Nerd Font / Powerline-patched monospace font.

### 3. Reload tmux (running server)

Existing tmux servers cache config (see #37). After font + config changes:

```bash
tmux set-environment -g TMUX_CONF_LOCAL "$HOME/dotfiles/.tmux.conf.local"
tmux source-file ~/.config/tmux/.tmux.conf
```

Or restart the tmux server:

```bash
bash ~/dotfiles/.tmux.reset.sh
# then start tmux again
```

## Verify

```bash
# Font installed
ls ~/Library/Fonts/'MesloLGS NF Regular.ttf'

# tmux loads repo override
tmux display-message -p '#{client_termname}'   # optional sanity
tmux show-options -g history-limit               # expect 50000 from .tmux.conf.local
```

Status bar should show smooth powerline arrows, not `?`.

## Not a font issue

A literal `?` in the **zsh prompt** next to git status often means **untracked
files** — p10k uses `?` by design (`POWERLEVEL9K_VCS_UNTRACKED_ICON='?'` in
`.p10k.zsh`). That is separate from tmux separator glyphs.

## Linux / WSL

`install.sh` skips Meslo download on non-macOS. Install a Nerd Font in your
terminal emulator and point the profile at it (e.g. `MesloLGS Nerd Font`,
`FiraCode Nerd Font`).
