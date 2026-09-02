# tmux powerline font SOP + install.sh automation

Status: done

## Problem

PR #159 powerline tmux theme shows `?` glyphs when terminal uses Monaco/unpatched font.

## Solution

- `install.sh`: `setup_terminal_fonts` — MesloLGS NF download + iTerm2 profile update
- Spec/SOP: `docs/specs/done/2026-09-02-tmux-powerline-font-sop.md`
- Tests: `tests/test-install-meslo-fonts.sh`
