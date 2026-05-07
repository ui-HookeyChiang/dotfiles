# Dotfiles (Linux + macOS)

Single-command bootstrap for a modern shell + editor + dev-tools setup: zsh with zinit auto-bootstrap, Neovim with LSP, tmux with oh-my-tmux, AI-powered git commit messages, and Claude Code CLI integration. Targets Ubuntu/Debian and macOS.

> **Note**: Neovim configuration is based on [glepnir-nvim](https://github.com/glepnir-nvim).

## Quick Start

```bash
git clone --recurse-submodules git@github.com:ui-HookeyChiang/dotfiles.git
cd dotfiles
./install.sh                          # core only
./install.sh --all                    # core + all optional modules
./install.sh --with-node --with-rust  # core + selected modules
./install.sh --dry-run                # preview without changes
exec $SHELL                           # reload
```

`./install.sh --help` lists every flag. The script is idempotent — re-run it safely.

## What install.sh does

| Step | Linux | macOS |
|---|---|---|
| OS packages | `apt`: zsh tmux neovim ripgrep fd-find fzf bat jq zoxide tldr git | `brew`: same names + auto-installs Homebrew if missing |
| Default shell | `chsh` to zsh | `chsh` + adds zsh to `/etc/shells` |
| Submodules | `.config/nvim` + `.config/tmux` | same |
| Symlinks | whitelist symlink to `$HOME`, conflicts go to `~/.dotfiles-backup-<ts>/` | same |

| Optional flag | What it adds |
|---|---|
| `--with-node` | Node.js LTS + `@anthropic-ai/claude-code` |
| `--with-go` | Go + `golines` |
| `--with-rust` | `rustup` + `stylua` + `rustfmt` |
| `--with-docker` | Docker Engine (Linux only) |
| `--with-latex` | MacTeX (macOS only) |
| `--all` | All OS-compatible optional modules |

The core symlink step uses an explicit whitelist (`.zshrc`, `.vimrc`, `.gitconfig`, `.tmux.conf.local`, etc.) — no more recursive copy of every dotfile (which used to drag in `.git` and overwrite arbitrary files). Existing files are moved to `~/.dotfiles-backup-<timestamp>/` before linking.

## What you get

| Component | Features |
|-----------|----------|
| **Zsh Shell** | Autosuggestions, syntax highlighting, smart completions, directory jumping (zinit auto-bootstrap on first launch — no manual plugin clones) |
| **Neovim** | LSP support for 30+ languages, modular configuration, modern UI |
| **Tmux** | Enhanced terminal multiplexer with oh-my-tmux theming |
| **Git** | 20+ useful aliases, AI-powered commit messages, SSH signing |

### Key Git Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `git st` | `git status` | Show working tree status |
| `git ci` | `git commit` | Record changes to repository |
| `git co` | `git checkout` | Switch branches or restore files |
| `git br` | `git branch` | List, create, or delete branches |
| `git au` | `git add -u` | Stage modified and deleted files |
| `git ap` | `git add -p` | Interactively stage changes |

### Configuration Files

Key configuration files and their purposes:

- `.zshrc` — Zsh shell configuration (zinit-managed plugins)
- `.vimrc` / `.config/nvim/` — Editor configurations
- `.gitconfig` — Git aliases, settings, and SSH signing
- `.config/tmux/tmux.conf.local` — Tmux customizations
- `.zprofile` — Cross-shell environment variables

## AI-Powered Workflow

### Claude Code CLI

Installed via `./install.sh --with-node`. An AI-powered command-line interface for coding tasks, code review, refactoring, and more.

```bash
# Start interactive session
claude

# Execute specific tasks
claude "refactor this function for better readability"
claude "explain this codebase"
claude "add tests for module X"

# Code review
claude "review my staged changes"
```

Set your API key once:

```bash
export ANTHROPIC_API_KEY="your-api-key-here"
echo 'export ANTHROPIC_API_KEY="your-api-key-here"' >> ~/.zshrc
```

Get an API key from the [Anthropic Console](https://console.anthropic.com/).

**Features**: context-aware across the whole codebase, multi-language, conversational, can read/write files, integrates with git/npm/cargo/etc.

### AI-Powered Git Commits

`~/.ai-commit.sh` generates conventional-commit messages from your staged diff using the Claude API. Setup is the same `ANTHROPIC_API_KEY` as above.

```bash
# Stage your changes first
git add .

# Generate AI commit message for staged changes
~/.ai-commit.sh

# Rewrite a historic commit with AI-generated message
~/.ai-commit.sh <commit-hash>
```

**Features**: smart diff analysis with recent-history context, conventional-commit format (`feat:`, `fix:`, `docs:`, ...), historic message rewriting, preserves your working directory state.

## Manual setup (for the curious)

<details>
<summary>Click to expand — what install.sh does under the hood, and how to recover when it fails</summary>

These are the original step-by-step setup instructions. `./install.sh` automates all of this; the steps below are useful for understanding internals or recovering when the script fails on an unusual platform.

### 1. System Package Installation

```bash
sudo apt update
sudo apt install -y python3-venv python3-pip clang npm unzip ripgrep fzf bat \
    fd-find cmake gettext curl ca-certificates git-buildpackage cargo tmux zsh \
    tldr jless zoxide
```

### 2. Shell Setup (Zsh + zinit)

```bash
# Set Zsh as default shell
sudo chsh -s $(which zsh)
```

`.zshrc` auto-bootstraps zinit on first launch and installs all configured plugins (autosuggestions, syntax highlighting, completions, fast directory jumping). No manual plugin clones needed.

### 3. Neovim Installation

#### ARM64 Systems (Build from Source)
```bash
sudo apt install -y cmake gettext clang clangd
git clone https://github.com/neovim/neovim.git
cd neovim
make CMAKE_BUILD_TYPE=RelWithDebInfo
sudo make install

# Setup clangd for LSP
ln -s /usr/bin/clangd ~/.local/share/nvim/mason/bin/clangd
mkdir -p ~/.local/share/nvim/mason/packages/clangd
```

#### x86_64 Systems (AppImage)
```bash
curl -LO https://github.com/neovim/neovim/releases/download/nightly/nvim.appimage
chmod u+x nvim.appimage
./nvim.appimage --appimage-extract
sudo rm -rf /squashfs-root
sudo mv squashfs-root /
sudo ln -s /squashfs-root/AppRun /usr/bin/nvim
rm nvim.appimage
```

### 4. Development Tools Setup

#### Node.js and npm
```bash
# Install Node.js LTS via NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
```

#### TypeScript and Language Servers
```bash
npm install -g typescript typescript-language-server prettier eslint
```

#### Claude Code (AI-powered CLI)
```bash
npm install -g @anthropic-ai/claude-code
export ANTHROPIC_API_KEY="your-api-key-here"
```

#### Go and Tools
```bash
sudo snap install go --classic
go install github.com/segmentio/golines@latest
```

#### Rust and Formatters
```bash
cargo install stylua rustfmt
```

### 5. Tmux Configuration

```bash
# oh-my-tmux is wired in as a submodule under .config/tmux
git submodule update --init .config/tmux
```

### 6. Docker Setup (Linux, optional)

```bash
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -a -G docker $(whoami)
newgrp docker
```

### 7. Per-language quick reference

#### C/C++
```bash
~/.ctags.sh   # Generate ctags + cscope databases for code navigation
```

#### Go
- **golines** — automatic line-length formatting
- **LSP** — full language-server support in Neovim

#### Rust
- **stylua** — Lua code formatting
- **rustfmt** — Rust code formatting
- **Cargo** — integrated package management

#### Web
- **TypeScript** — full TS/JS support with LSP
- **Node.js** — latest LTS via NodeSource
- **Modern tooling** — fzf, ripgrep, bat integration

</details>

## Project layout

- `install.sh` — bootstrap script (this README's Quick Start)
- `docs/specs/` — design specs (active and historical)
- `.config/nvim/` — neovim config (submodule)
- `.config/tmux/` — oh-my-tmux (submodule)
- `.claude/` — Claude Code settings + custom permissions
