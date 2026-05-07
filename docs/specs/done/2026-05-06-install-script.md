---
kind: spec
status: proposed
---

# Design: dotfiles install.sh + repo improvements

**Date:** 2026-05-06
**Status:** Approved (brainstorming complete)
**Owner:** hookey.chiang@ui.com

## Context

The `dotfiles` repo currently relies on a manual 7-section README walkthrough for new-machine setup. The README has drifted from reality:

- README documents `oh-my-zsh` + manual `git clone` of 4 plugins, but `.zshrc` already uses `zinit`.
- Quick Start uses `cp -r .* ~`, which copies `.git` and overwrites existing configs unsafely.
- Setup steps are spread across system packages, zsh, nvim, node, go, rust, docker — pure copy-paste.
- README header says "for Linux Development" but later has macOS LaTeX section.

## Goal

Provide a single `install.sh` that bootstraps a new Ubuntu/Debian or macOS machine in one command, idempotently, with opt-in optional modules. Update README to match.

## Non-Goals

- No module-decomposition into multiple scripts (YAGNI at this size).
- No `uninstall.sh` (symlinks unlink trivially; revisit if needed).
- No `update` subcommand (`git pull && ./install.sh` is already idempotent).
- No `stow` / `chezmoi` migration (scale doesn't justify new tooling).

## Architecture

Single bash file (~250 lines), top-down structure:

```
install.sh
├─ flag parsing (--with-*, --dry-run, --no-symlink, --all, -h)
├─ detect_os()              uname -s + /etc/os-release → "linux" | "macos"
├─ ensure_pkg_manager()     apt update; macOS: install Homebrew if missing
├─ install_core_packages()  zsh tmux nvim ripgrep fd fzf bat jq zoxide tldr
├─ setup_zsh()              chsh; zinit bootstraps via .zshrc itself
├─ install_nvim()           Linux: apt; macOS: brew
├─ init_submodules()        git submodule update --init
├─ symlink_dotfiles()       whitelist + timestamped backup
├─ [opt] install_node()     NodeSource LTS + npm i -g @anthropic-ai/claude-code
├─ [opt] install_go()       apt/brew + go install golines
├─ [opt] install_rust()     rustup + cargo install stylua + rustfmt
├─ [opt] install_docker()   Linux only; macOS prints Desktop hint and skips
└─ [opt] install_latex()    macOS only (MacTeX); Linux prints hint and skips
```

### Error Handling

- `set -euo pipefail` + `trap 'echo "FAILED at line $LINENO"' ERR`.
- Each step logs `==> <step name>` on entry.
- `sudo -v` once at the top + background keep-alive loop, so the user doesn't get prompted mid-flow.

## Symlink Strategy (the core 闭环)

Whitelist-based — never `cp -r .*`. Two lists:

```bash
DOTFILES=(
  .zshrc .zprofile .vimrc .gitconfig .gitignore .inputrc
  .p10k.zsh .clang-format .clangd .ctags.sh
  .ai-commit.sh .ai-commit-msg.sh
  .git-completion.sh .git-prompt.sh .git_allowed_signers
)
DIRS=(
  .config/nvim .config/tmux .claude
)
```

For each entry, three branches:

1. Target missing → `ln -s "$REPO/$entry" "$HOME/$entry"`.
2. Target is symlink already pointing into this repo → skip (idempotent).
3. Target is real file/dir → move to `~/.dotfiles-backup-<UTC-timestamp>/` preserving relative path, then symlink.

Backup directory is created lazily (only if a conflict actually happens), so re-runs don't litter empty backup dirs.

## CLI

```
./install.sh [OPTIONS]

Core (always run): system packages, zsh+zinit, nvim, submodules, symlinks

Optional modules:
  --with-node       Node.js LTS + @anthropic-ai/claude-code
  --with-go         Go + golines
  --with-rust       rustup + stylua + rustfmt
  --with-docker     Docker Engine (Linux only)
  --with-latex      MacTeX (macOS only)
  --all             Enable all compatible optional modules (skips OS-incompatible)

Flags:
  --dry-run         Print actions, do not execute
  --no-symlink      Skip dotfile symlinking
  -h, --help        Show usage
```

## README Updates

| Problem | Fix |
|---|---|
| Documents oh-my-zsh + 4 manual `git clone` plugins | Replace with one line: `.zshrc` auto-bootstraps zinit |
| `cp -r .* ~` in Quick Start | Replace with `./install.sh` |
| Setup spread across 7 sections | Collapse to "Quick Start = `./install.sh`" + collapsible "Manual setup (for the curious)" |
| "for Linux Development" header but has macOS section | Update header to "Linux + macOS" |
| `cp -r .* ~` would copy `.git`, `.gitmodules` | Whitelist symlink avoids this |

## Verification (拿结果)

After implementation, run:

1. **Dry-run on current Mac**: `./install.sh --dry-run` — confirm plan reads correctly, no surprises.
2. **Ubuntu container**: `docker run --rm -it -v $PWD:/dotfiles ubuntu:22.04` then `cd /dotfiles && ./install.sh`. Verify shell reload works, nvim launches.
3. **Idempotency**: run install twice on the same machine; second run should report all skips, no errors.
4. **Backup behavior**: pre-create a fake `~/.zshrc` containing a marker string; run install; confirm marker file ends up under `~/.dotfiles-backup-*/`.

## Open Questions

None at design time. Surface during implementation if any assumption fails.

## Implementation Plan Reference

See `writing-plans` output (next step in workflow).
