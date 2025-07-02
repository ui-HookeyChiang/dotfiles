# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository for Linux development environments. It provides comprehensive shell, editor, and development tool configurations optimized for polyglot programming with emphasis on modern tooling and AI-assisted workflows.

## Key Configuration Areas

### Shell Environment
- **Primary shell**: Zsh with oh-my-zsh framework (robbyrussell theme)
- **Fallback**: Bash with custom prompt and git integration
- **Key files**: `.zshrc`, `.bashrc`, `.profile`
- **Plugins**: zsh-autosuggestions, zsh-syntax-highlighting, zsh-z, completions

### Editor Configuration
- **Primary editor**: Neovim with modular Lua configuration (`.config/nvim/`)
- **Architecture**: Based on glepnir-nvim, organized in modules (ai, editor, lsp, tools, ui, mytools)
- **Language support**: 30+ languages with LSP integration
- **Fallback**: Vim with vim-plug and coc.nvim (`.vimrc`)

### Development Tools
- **Git**: Extensive aliases and SSH key signing (`.gitconfig`)
- **Tmux**: oh-my-tmux framework with custom local config
- **Language tools**: Go, Rust (Cargo), Node.js, Python, C/C++

## AI-Powered Git Workflow

### Core Scripts
- `.ai-commit.sh` - Main commit automation script
- `.ai-commit-msg.sh` - Generates commit messages using Claude API

### Usage
```bash
# For staged changes
~/.ai-commit.sh

# For rewriting historic commit
~/.ai-commit.sh <commit-hash>
```

### Requirements
- Set `ANTHROPIC_API_KEY` environment variable
- Uses Claude Sonnet model for commit message generation
- Follows conventional commit format (feat:, fix:, docs:, etc.)

## Development Commands

### C/C++ Development
```bash
# Generate ctags and cscope databases
~/.ctags.sh
```

### Git Operations
Common aliases available (defined in `.gitconfig`):
- `git au` - add -u
- `git ap` - add -p
- `git br` - branch
- `git ci` - commit
- `git co` - checkout
- `git st` - status

### tmux Management
```bash
# Reset tmux key bindings
./tmux.reset
```

## Installation Architecture

The dotfiles use a manual copy approach rather than symlinks:
```bash
git clone <repo>
cd dotfiles
git submodule update --init
cp -r .* ~
```

## Environment Requirements

### Prerequisites (from README.md)
- Zsh, oh-my-zsh with plugins
- Neovim (built from source for arm64, AppImage for x86_64)
- Development tools: `python3-venv`, `clang`, `npm`, `ripgrep`, `fzf`, `bat`, `fd-find`
- Language-specific: `go`, `cargo`, `stylua`, `rustfmt`
- Optional: Docker, tmux, git-buildpackage, Nix

### Path Configuration
- Go binaries: `$GOPATH/bin`
- Rust binaries: `$HOME/.cargo/bin`
- Homebrew: `/opt/homebrew/bin` (macOS)

## Code Style Guidelines

- **No trailing spaces**: Never add trailing whitespace to any lines in files
- **Clean formatting**: Maintain consistent indentation and spacing
- **Line endings**: Use Unix-style line endings (LF)

## Key Features for Claude Code

1. **Modular Design**: Configurations are well-organized and modular
2. **Cross-platform**: Linux focus with macOS compatibility considerations
3. **Modern Tooling**: Uses contemporary CLI tools (ripgrep, fzf, bat, etc.)
4. **AI Integration**: Built-in Claude API usage for commit messages
5. **Developer Productivity**: Extensive aliases, key bindings, and automation scripts