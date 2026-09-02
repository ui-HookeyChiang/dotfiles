# tmux powerline font SOP + install.sh automation

Status: done

## Problem

PR #159 powerline tmux theme shows `?` glyphs when terminal uses an unpatched font.

## Solution

- `install.sh`: `setup_terminal_fonts` — Meslo on macOS + Linux/WSL, iTerm2 + Windows Terminal profile update
- `scripts/install-meslo-fonts.ps1` — native Windows helper
- Spec/SOP: `docs/specs/done/2026-09-02-tmux-powerline-font-sop.md`
- Tests: `tests/test-install-meslo-fonts.sh`
