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
**Scope:** macOS, Linux, WSL, and native Windows terminals + tmux (oh-my-tmux + p10k)

## Symptom

After PR #159, the tmux status bar and window list show **question marks** where
powerline separator arrows should appear. p10k may look fine in some tabs but tmux
does not.

## Root cause

`.tmux.conf.local` configures oh-my-tmux powerline separators using Private Use
Area code points (`U+E0B0`–`U+E0B3`). Those glyphs exist only in **Nerd Font /
Powerline-patched** fonts (MesloLGS NF matches p10k's `POWERLEVEL9K_MODE=powerline`).

If the terminal profile uses an unpatched font (e.g. **Monaco**, **Menlo**,
**Cascadia Mono** without Nerd Font patch), the OS renders missing glyphs as `?`.

This is **not** a tmux config bug.

## Automated fix (preferred)

### macOS / Linux / WSL

Core `install.sh` now:

| OS | Fonts installed to | Terminal auto-config |
|---|---|---|
| macOS | `~/Library/Fonts/` | iTerm2 profile (when not already Meslo) |
| Linux | `~/.local/share/fonts/meslo-lgs-nf/` + `fc-cache` | Manual (see below) |
| WSL | Linux path **and** `%LOCALAPPDATA%\Microsoft\Windows\Fonts` | Windows Terminal `settings.json` (when found) |

```bash
cd ~/dotfiles && ./install.sh
```

Open a **new terminal tab/window** after install (existing tabs keep the old font).

### Native Windows (no WSL)

`install.sh` does not run on Windows. Use the PowerShell helper:

```powershell
pwsh -File $HOME\dotfiles\scripts\install-meslo-fonts.ps1
```

Then open a **new Windows Terminal tab**.

## Manual fix

### 1. Install MesloLGS NF

**macOS**

```bash
mkdir -p ~/Library/Fonts
base='https://github.com/romkatv/powerlevel10k-media/raw/master'
for variant in Regular Bold Italic 'Bold Italic'; do
  curl -fsSL "$base/MesloLGS%20NF%20${variant// /%20}.ttf" \
    -o "$HOME/Library/Fonts/MesloLGS NF ${variant}.ttf"
done
```

**Linux**

```bash
mkdir -p ~/.local/share/fonts/meslo-lgs-nf
base='https://github.com/romkatv/powerlevel10k-media/raw/master'
for variant in Regular Bold Italic 'Bold Italic'; do
  curl -fsSL "$base/MesloLGS%20NF%20${variant// /%20}.ttf" \
    -o "$HOME/.local/share/fonts/meslo-lgs-nf/MesloLGS NF ${variant}.ttf"
done
fc-cache -f ~/.local/share/fonts/meslo-lgs-nf
```

**WSL** — do the Linux steps above **and** copy fonts into Windows so Windows
Terminal can use them:

```bash
win_fonts="/mnt/c/Users/$USER/AppData/Local/Microsoft/Windows/Fonts"
mkdir -p "$win_fonts"
cp ~/.local/share/fonts/meslo-lgs-nf/*.ttf "$win_fonts/"
```

**Native Windows (PowerShell)**

```powershell
pwsh -File $HOME\dotfiles\scripts\install-meslo-fonts.ps1
```

### 2. Set terminal font

| Terminal | Setting |
|---|---|
| **iTerm2** (macOS) | Settings → Profiles → Text → Font → **MesloLGS NF** (14pt) |
| **Windows Terminal** (WSL / Windows) | Settings → Defaults → Appearance → Font face → **MesloLGS NF** |
| **GNOME Terminal / Tilix** | Profile preferences → Custom font → **MesloLGS NF** |
| **Kitty** | `font_family MesloLGS NF` in `kitty.conf` |
| **Alacritty** | `font.normal.family = "MesloLGS NF"` in `alacritty.toml` |
| **Cursor / VS Code** | `"terminal.integrated.fontFamily": "MesloLGS NF"` |

Any Nerd Font / Powerline-patched monospace works; MesloLGS NF matches p10k.

### 3. Reload tmux (running server)

```bash
tmux set-environment -g TMUX_CONF_LOCAL "$HOME/dotfiles/.tmux.conf.local"
tmux source-file ~/.config/tmux/.tmux.conf
```

Or restart the tmux server:

```bash
bash ~/dotfiles/.tmux.reset.sh
```

## Verify

```bash
fc-list | grep -i meslo          # Linux/WSL
ls ~/Library/Fonts/'MesloLGS NF Regular.ttf'   # macOS
tmux show-options -g history-limit             # expect 50000
```

## Not a font issue

A literal `?` in the **zsh prompt** next to git status often means **untracked
files** — p10k uses `?` by design. That is separate from tmux separator glyphs.

## Platform notes

- **WSL:** Windows Terminal uses Windows-installed fonts — copy into
  `%LOCALAPPDATA%\Microsoft\Windows\Fonts` even when Linux fontconfig already works.
- **Linux (non-WSL):** `install.sh` runs `fc-cache`; set the profile font manually.
- **Native Windows:** use `scripts/install-meslo-fonts.ps1`; tmux runs in WSL — reload from there.
