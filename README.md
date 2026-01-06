# Personal Dotfiles for Linux Development

A comprehensive dotfiles repository providing optimized configurations for shell environments, editors, and development tools. Includes AI-powered git workflow automation and modern tooling setup.

## Features

- **Shell Environment**: Zsh with oh-my-zsh, custom bash configuration
- **Editors**: Neovim (primary) with LSP support, Vim fallback configuration
- **Development Tools**: Git with extensive aliases, tmux with oh-my-tmux
- **AI Integration**: 
  - Claude Code CLI for AI-assisted development
  - Claude-powered commit message generation
- **Language Support**: Go, Rust, JavaScript/TypeScript, Python, C/C++

> **Note**: Neovim configuration is based on [glepnir-nvim](https://github.com/glepnir-nvim)

## Prerequisites

- Linux system (Ubuntu/Debian recommended)
- Git installed
- Sudo privileges for package installation
- Basic command line familiarity

## Quick Start

```bash
# Clone the repository
git clone git@github.com:ui-HookeyChiang/dotfiles.git
cd dotfiles

# Initialize submodules and install
git submodule update --init
cp -r .* ~

# Reload shell to apply changes
exec $SHELL
```

## Installation Guide

### 1. System Package Installation

#### Core Development Tools
```bash
sudo apt update
sudo apt install -y python3-venv python3-pip clang npm unzip ripgrep fzf bat \
    fd-find cmake gettext curl ca-certificates git-buildpackage cargo tmux zsh \
    tldr jless zoxide
```

### 2. Shell Setup (Zsh + Oh-My-Zsh)

```bash
# Set Zsh as default shell
sudo chsh -s $(which zsh)

# Install Oh-My-Zsh framework
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

#### Install Essential Plugins
```bash
# Autosuggestions based on command history
git clone https://github.com/zsh-users/zsh-autosuggestions \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# Syntax highlighting for commands
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Fast directory jumping
git clone https://github.com/agkozak/zsh-z \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-z

# Additional completions
git clone https://github.com/zsh-users/zsh-completions \
  ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
```

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
# Install Node.js LTS via NodeSource repository (recommended)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version
npm --version

# Alternative: Update npm to latest version
sudo npm install -g npm@latest

# Alternative: Use n version manager (if you need multiple Node versions)
sudo npm cache clean -f
sudo npm install -g n
sudo n stable
```

#### TypeScript and Language Servers
```bash
# Install TypeScript globally
npm install -g typescript typescript-language-server

# Install other useful development tools
npm install -g prettier eslint
```

#### Claude Code (AI-powered CLI)
```bash
# Install claude-code globally via npm
npm install -g @anthropic-ai/claude-code

# Verify installation
claude-code --version

# Setup API key (required for AI features)
export ANTHROPIC_API_KEY="your-api-key-here"
echo 'export ANTHROPIC_API_KEY="your-api-key-here"' >> ~/.zshrc
```

> **Note**: Get your API key from [Anthropic Console](https://console.anthropic.com/)

#### Go and Tools
```bash
sudo snap install go --classic
go install github.com/segmentio/golines@latest
```

#### Rust and Formatters
```bash
cargo install stylua rustfmt
```

#### Nix Package Manager
```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --no-daemon
```

### 5. Tmux Configuration

```bash
# Install oh-my-tmux framework
git clone https://github.com/gpakosz/.tmux.git ~/.oh-my-tmux

# Setup configuration
mkdir -p ~/.config/tmux
ln -s ~/.oh-my-tmux/.tmux.conf ~/.config/tmux/tmux.conf
cp ~/.oh-my-tmux/.tmux.conf.local ~/.config/tmux/tmux.conf.local
cat ~/.config/tmux.default/.tmux.conf.local >> ~/.config/tmux/tmux.conf.local
```

### 6. Docker Setup (Optional)
```bash
# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -a -G docker `whoami`
newgrp docker
```

### 7. Security Setup (Optional)

#### Create Backup Sudoers Account
```bash
# Replace PASSWORD with actual password
sudo useradd --system -p PASSWORD -G sudo `whoami`2
```

> ⚠️ **Warning**: Replace `PASSWORD` with an actual secure password before running this command.

## 🤖 AI-Powered Development Workflow

This dotfiles setup provides two powerful AI tools for enhanced development productivity.

### Claude Code CLI

An AI-powered command-line interface that helps with coding tasks, code review, refactoring, and more.

#### Installation
```bash
# Install via npm (see "Development Tools Setup" section)
npm install -g @anthropic-ai/claude-code

# Configure API key
export ANTHROPIC_API_KEY="your-api-key-here"
```

#### Usage Examples
```bash
# Start interactive session
claude-code

# Execute specific tasks
claude-code "refactor this function for better readability"
claude-code "explain this codebase"
claude-code "add tests for module X"

# Code review
claude-code "review my staged changes"

# Work with specific files
claude-code "optimize performance in ./src/main.rs"
```

#### Key Features
- **Context-Aware**: Understands your entire codebase
- **Multi-Language**: Supports all languages configured in Neovim
- **Interactive**: Conversational interface for complex tasks
- **File Operations**: Can read, write, and modify files
- **Tool Integration**: Works with git, npm, cargo, and other dev tools

### AI-Powered Git Commits

Intelligent commit message generation using Claude API, automatically creating conventional commit messages based on your code changes.

#### Setup

1. **Get Anthropic API Key**:
   - Visit [Anthropic Console](https://console.anthropic.com/)
   - Create an API key
   - Add to your shell profile:
   ```bash
   echo 'export ANTHROPIC_API_KEY="your-api-key-here"' >> ~/.zshrc
   source ~/.zshrc
   ```

2. **Usage Examples**:
   ```bash
   # Stage your changes first
   git add .

   # Generate AI commit message for staged changes
   ~/.ai-commit.sh

   # Rewrite a historic commit with AI-generated message
   ~/.ai-commit.sh <commit-hash>
   ```

#### Features
- **Smart Analysis**: Analyzes git diff and recent commit history for context
- **Conventional Commits**: Follows standard format (feat:, fix:, docs:, etc.)
- **Context-Aware**: Generates messages that reflect actual code changes
- **Historic Rewriting**: Can improve existing commit messages
- **Safe Operations**: Preserves your working directory state

## LaTeX Support (macOS)

### Install Latexmk
See [Latexmk documentation](https://mg.readthedocs.io/latexmk.html)

### PDF Readers for LaTeX

#### Skim with TeXSync
```bash
brew install skim
# Configure: PDF-TeX cmd=nvim args=--headless -c "VimtexInverseSearch %line '%file'"
```

#### Zathura
See [zathura setup guide](https://github.com/zegervdv/homebrew-zathura) and run:
```vim
:help vimtex-faq-zathura-macos
```

## 🚀 Usage & Features

### What You Get

After installation, your development environment includes:

| Component | Features |
|-----------|----------|
| **Zsh Shell** | Autosuggestions, syntax highlighting, smart completions, directory jumping |
| **Neovim** | LSP support for 30+ languages, modular configuration, modern UI |
| **Tmux** | Enhanced terminal multiplexer with oh-my-tmux theming |
| **Git** | 20+ useful aliases, AI-powered commit messages, SSH signing |

### ⚡ Key Git Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `git st` | `git status` | Show working tree status |
| `git ci` | `git commit` | Record changes to repository |
| `git co` | `git checkout` | Switch branches or restore files |
| `git br` | `git branch` | List, create, or delete branches |
| `git au` | `git add -u` | Stage modified and deleted files |
| `git ap` | `git add -p` | Interactively stage changes |

### 🛠️ Development Tools by Language

#### C/C++ Development
```bash
# Generate ctags and cscope databases for code navigation
~/.ctags.sh
```

#### Go Development
- **golines**: Automatic line length formatting
- **LSP**: Full language server support in Neovim

#### Rust Development
- **stylua**: Lua code formatting
- **rustfmt**: Rust code formatting
- **Cargo**: Integrated package management

#### Web Development
- **TypeScript**: Full TS/JS support with LSP
- **Node.js**: Latest LTS version management
- **Modern tooling**: Integration with fzf, ripgrep, bat

### 📝 Configuration Files

Key configuration files and their purposes:

- `.zshrc` - Zsh shell configuration with plugins
- `.vimrc` / `.config/nvim/` - Editor configurations
- `.gitconfig` - Git aliases, settings, and SSH signing
- `.tmux.conf.local` - Tmux customizations
- `.profile` - Cross-shell environment variables