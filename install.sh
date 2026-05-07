#!/usr/bin/env bash
#
# install.sh — single-command bootstrap for this dotfiles repo on Ubuntu/Debian
# or macOS. Idempotent: safe to re-run.
#
# Spec: docs/specs/active/2026-05-06-install-script.md
#
# Core (always run): system packages, zsh, submodules, symlinks.
# Optional modules (--with-*) are stubs in this task; filled in by Task 2.

set -euo pipefail
trap 'echo "FAILED at line $LINENO" >&2' ERR

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
NO_SYMLINK=0
WITH_NODE=0
WITH_GO=0
WITH_RUST=0
WITH_DOCKER=0
WITH_LATEX=0

OS=""             # "linux" | "macos"
DISTRO_ID=""      # e.g. "ubuntu", "debian"
BACKUP_DIR=""     # lazily set on first symlink conflict
BACKUP_TS=""      # UTC timestamp captured once at start

# Whitelisted top-level dotfiles (live at $HOME/<name>).
DOTFILES=(
  .zshrc .zprofile .vimrc .gitconfig .gitignore .inputrc
  .p10k.zsh .clang-format .clangd .ctags.sh
  .ai-commit.sh .ai-commit-msg.sh
  .git-completion.sh .git-prompt.sh .git_allowed_signers
)

# Whitelisted directory entries (live at $HOME/<name>).
DIRS=(
  .config/nvim
  .config/tmux
  .claude
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  printf '==> %s\n' "$*" >&2
}

note() {
  printf '    %s\n' "$*" >&2
}

err() {
  printf 'ERROR: %s\n' "$*" >&2
}

# run <cmd...>: execute or, in --dry-run mode, echo "+ <cmd>" without running.
run() {
  if (( DRY_RUN )); then
    printf '+ %s\n' "$*" >&2
  else
    "$@"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Single-command bootstrap for this dotfiles repo. Idempotent.

Core (always run unless --no-symlink):
  - system packages (zsh, tmux, neovim, ripgrep, fd, fzf, bat, jq, zoxide, tldr, git)
  - zsh as default shell (.zshrc auto-bootstraps zinit on first launch)
  - git submodules (.config/nvim, .config/tmux)
  - dotfile symlinks (whitelist + timestamped backup on conflict)

Optional modules:
  --with-node     Node.js LTS + @anthropic-ai/claude-code (Task 2)
  --with-go       Go + golines (Task 2)
  --with-rust     rustup + stylua + rustfmt (Task 2)
  --with-docker   Docker Engine, Linux only (Task 2)
  --with-latex    MacTeX, macOS only (Task 2)
  --all           Enable all OS-compatible optional modules

Flags:
  --dry-run       Print actions, do not execute
  --no-symlink    Skip dotfile symlinking
  -h, --help      Show this help and exit
EOF
}

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------

parse_flags() {
  while (( $# )); do
    case "$1" in
      --dry-run)      DRY_RUN=1 ;;
      --no-symlink)   NO_SYMLINK=1 ;;
      --with-node)    WITH_NODE=1 ;;
      --with-go)      WITH_GO=1 ;;
      --with-rust)    WITH_RUST=1 ;;
      --with-docker)  WITH_DOCKER=1 ;;
      --with-latex)   WITH_LATEX=1 ;;
      --all)
        WITH_NODE=1
        WITH_GO=1
        WITH_RUST=1
        WITH_DOCKER=1
        WITH_LATEX=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "unknown flag: $1"
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
}

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------

detect_os() {
  log "detect_os"
  local uname_s
  uname_s="$(uname -s)"
  case "$uname_s" in
    Linux)
      OS="linux"
      if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        DISTRO_ID="$(. /etc/os-release && printf '%s' "${ID_LIKE:-$ID}")"
      fi
      note "OS=linux distro_id=${DISTRO_ID:-unknown}"
      case " $DISTRO_ID " in
        *debian*|*ubuntu*) ;;
        *)
          err "unsupported Linux distro '$DISTRO_ID'; only Debian/Ubuntu family is supported"
          exit 1
          ;;
      esac
      ;;
    Darwin)
      OS="macos"
      note "OS=macos"
      ;;
    *)
      err "unsupported OS: $uname_s"
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# sudo keep-alive
# ---------------------------------------------------------------------------

sudo_keepalive() {
  log "sudo_keepalive"
  if (( DRY_RUN )); then
    note "dry-run: skip sudo -v"
    return 0
  fi
  if [[ "$(id -u)" == "0" ]]; then
    note "running as root; skip sudo keep-alive"
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    note "sudo not available; skip"
    return 0
  fi
  sudo -v
  # Background keep-alive: refresh sudo timestamp every 60s, exit when parent dies.
  ( while true; do
      sudo -n true 2>/dev/null || exit
      sleep 60
      kill -0 "$$" 2>/dev/null || exit
    done ) &
  disown 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Package manager bootstrap
# ---------------------------------------------------------------------------

ensure_pkg_manager() {
  log "ensure_pkg_manager"
  case "$OS" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        note "brew already installed"
      else
        note "installing Homebrew"
        if (( DRY_RUN )); then
          # Dry-run prints the literal command; expansion is intentional.
          # shellcheck disable=SC2016
          printf '+ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n' >&2
        else
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        # Add brew to PATH for current session (Apple Silicon vs Intel).
        if [[ -x /opt/homebrew/bin/brew ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
          eval "$(/usr/local/bin/brew shellenv)"
        fi
      fi
      ;;
    linux)
      note "running apt-get update"
      run sudo apt-get update -y
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Core packages
# ---------------------------------------------------------------------------

# is_installed_apt <pkg>
is_installed_apt() {
  dpkg -s "$1" >/dev/null 2>&1
}

# is_installed_brew <pkg>
is_installed_brew() {
  brew list --formula "$1" >/dev/null 2>&1
}

install_core_packages() {
  log "install_core_packages"
  local pkgs
  case "$OS" in
    linux)
      pkgs=(zsh tmux neovim ripgrep fd-find fzf bat jq zoxide tldr git)
      local missing=()
      for p in "${pkgs[@]}"; do
        if is_installed_apt "$p"; then
          note "skip $p (installed)"
        else
          missing+=("$p")
        fi
      done
      if (( ${#missing[@]} )); then
        note "installing: ${missing[*]}"
        run sudo apt-get install -y "${missing[@]}"
      else
        note "all core packages already installed"
      fi
      ;;
    macos)
      pkgs=(zsh tmux neovim ripgrep fd fzf bat jq zoxide tldr git)
      for p in "${pkgs[@]}"; do
        if is_installed_brew "$p"; then
          note "skip $p (installed)"
        else
          note "installing $p"
          run brew install "$p"
        fi
      done
      ;;
  esac
}

# ---------------------------------------------------------------------------
# zsh setup
# ---------------------------------------------------------------------------

setup_zsh() {
  log "setup_zsh"
  local zsh_path
  if ! zsh_path="$(command -v zsh)"; then
    err "zsh not found after install_core_packages"
    return 1
  fi
  note ".zshrc auto-bootstraps zinit on first launch (no manual clone needed)"
  local current_shell
  current_shell="${SHELL:-}"
  if [[ "$current_shell" == "$zsh_path" ]] || [[ "${current_shell##*/}" == "zsh" ]]; then
    note "default shell is already zsh ($current_shell); skip chsh"
    return 0
  fi
  note "changing default shell to $zsh_path"
  case "$OS" in
    macos)
      # On macOS, zsh from Homebrew may not be in /etc/shells yet.
      if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
        note "adding $zsh_path to /etc/shells (sudo)"
        # Use stdin via heredoc to avoid quoting hazards if $zsh_path
        # ever contained special characters.
        if (( DRY_RUN )); then
          printf '+ sudo tee -a /etc/shells <<< %q\n' "$zsh_path" >&2
        else
          printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        fi
      fi
      run chsh -s "$zsh_path"
      ;;
    linux)
      # On Linux, /etc/shells normally already lists /bin/zsh after apt install.
      # `chsh` works for the current user without sudo.
      run chsh -s "$zsh_path"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Submodules
# ---------------------------------------------------------------------------

init_submodules() {
  log "init_submodules"
  if [[ ! -f "$REPO_ROOT/.gitmodules" ]]; then
    note "no .gitmodules; skip"
    return 0
  fi
  run git -C "$REPO_ROOT" submodule update --init --recursive
}

# ---------------------------------------------------------------------------
# Symlink dotfiles
# ---------------------------------------------------------------------------

ensure_backup_dir() {
  if [[ -n "$BACKUP_DIR" ]]; then
    return 0
  fi
  BACKUP_DIR="$HOME/.dotfiles-backup-$BACKUP_TS"
  note "creating backup dir: $BACKUP_DIR"
  run mkdir -p "$BACKUP_DIR"
}

# link_one <relpath>
link_one() {
  local rel="$1"
  local src="$REPO_ROOT/$rel"
  local dst="$HOME/$rel"

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    note "skip $rel (not in repo)"
    return 0
  fi

  # Ensure parent dir of $dst exists (for nested entries like .config/nvim).
  local parent
  parent="$(dirname "$dst")"
  if [[ ! -d "$parent" ]]; then
    run mkdir -p "$parent"
  fi

  if [[ ! -e "$dst" && ! -L "$dst" ]]; then
    # Branch 1: target missing.
    note "link $rel"
    run ln -s "$src" "$dst"
    return 0
  fi

  if [[ -L "$dst" ]]; then
    local target
    target="$(readlink "$dst")"
    # If symlink already points into the repo (resolves to $src or starts with REPO_ROOT)
    # AND the target actually exists, skip. A dangling symlink falls through to backup so
    # we don't keep a broken link pointing at a deleted/renamed repo file.
    if { [[ "$target" == "$src" ]] || [[ "$target" == "$REPO_ROOT/"* ]]; } && [[ -e "$src" ]]; then
      note "skip $rel (already linked)"
      return 0
    fi
    # Symlink points somewhere else: back it up and re-link.
    ensure_backup_dir
    note "backup foreign symlink $rel -> $target"
    run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    run mv "$dst" "$BACKUP_DIR/$rel"
    run ln -s "$src" "$dst"
    return 0
  fi

  # Branch 3: real file or directory exists.
  ensure_backup_dir
  note "backup $rel -> $BACKUP_DIR/$rel"
  run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  run mv "$dst" "$BACKUP_DIR/$rel"
  run ln -s "$src" "$dst"
}

symlink_dotfiles() {
  log "symlink_dotfiles"
  if (( NO_SYMLINK )); then
    note "--no-symlink set; skip"
    return 0
  fi
  local entry
  for entry in "${DOTFILES[@]}"; do
    link_one "$entry"
  done
  for entry in "${DIRS[@]}"; do
    link_one "$entry"
  done
  if [[ -z "$BACKUP_DIR" ]]; then
    note "no conflicts; no backup dir created"
  fi
}

# ---------------------------------------------------------------------------
# Optional modules (stubs; filled in by Task 2)
# ---------------------------------------------------------------------------

install_node() {
  log "install_node"
  if command -v node >/dev/null 2>&1; then
    note "skip node (installed: $(node --version 2>/dev/null || echo present))"
  else
    case "$OS" in
      linux)
        note "installing Node.js LTS via NodeSource"
        run bash -c "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
        run sudo apt-get install -y nodejs
        ;;
      macos)
        if is_installed_brew node; then
          note "skip node (brew formula present)"
        else
          note "installing node via brew"
          run brew install node
        fi
        ;;
    esac
  fi
  if command -v claude-code >/dev/null 2>&1 || claude-code --version >/dev/null 2>&1; then
    note "skip @anthropic-ai/claude-code (already installed)"
  else
    note "installing @anthropic-ai/claude-code globally"
    run npm install -g @anthropic-ai/claude-code
  fi
}

install_go() {
  log "install_go"
  if command -v go >/dev/null 2>&1; then
    note "skip go (installed: $(go version 2>/dev/null || echo present))"
  else
    case "$OS" in
      linux)
        note "installing golang-go via apt"
        run sudo apt-get install -y golang-go
        ;;
      macos)
        if is_installed_brew go; then
          note "skip go (brew formula present)"
        else
          note "installing go via brew"
          run brew install go
        fi
        ;;
    esac
  fi
  if command -v golines >/dev/null 2>&1; then
    note "skip golines (installed)"
  else
    note "installing golines via go install"
    run go install github.com/segmentio/golines@latest
    note "ensure \$(go env GOPATH)/bin is on PATH (e.g. export PATH=\$PATH:\$(go env GOPATH)/bin)"
  fi
}

install_rust() {
  log "install_rust"
  if command -v rustup >/dev/null 2>&1; then
    note "skip rustup (installed)"
  else
    note "installing rustup (stable, --no-modify-path)"
    run bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path"
  fi
  # Source cargo env so subsequent cargo/rustup calls work in the same script run.
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  note "ensuring rustfmt component is installed"
  run rustup component add rustfmt
  if command -v stylua >/dev/null 2>&1; then
    note "skip stylua (installed)"
  else
    note "installing stylua via cargo"
    run cargo install stylua
  fi
  note "ensure \$HOME/.cargo/bin is on PATH (rustup --no-modify-path skips shell rc edits)"
}

install_docker() {
  log "install_docker"
  if [[ "$OS" != "linux" ]]; then
    note "Docker Engine is Linux-only; on macOS install Docker Desktop manually"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    note "skip docker (installed: $(docker --version 2>/dev/null || echo present))"
    return 0
  fi
  note "installing Docker Engine via official apt repo"
  run sudo install -m 0755 -d /etc/apt/keyrings
  run sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  run sudo chmod a+r /etc/apt/keyrings/docker.asc
  run bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null'
  run sudo apt-get update
  run sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  run sudo usermod -aG docker "$USER"
  note "log out / back in (or 'newgrp docker') for the docker group to take effect"
}

install_latex() {
  log "install_latex"
  if [[ "$OS" != "macos" ]]; then
    note "MacTeX is macOS-only; on Linux use texlive via apt"
    return 0
  fi
  if command -v latexmk >/dev/null 2>&1; then
    note "skip latex (latexmk installed)"
    return 0
  fi
  note "WARNING: mactex-no-gui cask is ~5GB; download may take a while"
  run brew install --cask mactex-no-gui
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_flags "$@"

  BACKUP_TS="$(date -u +%Y%m%dT%H%M%SZ)"

  log "install.sh start (dry_run=$DRY_RUN no_symlink=$NO_SYMLINK)"
  note "repo root: $REPO_ROOT"

  detect_os
  sudo_keepalive
  ensure_pkg_manager
  install_core_packages
  setup_zsh
  init_submodules
  symlink_dotfiles

  (( WITH_NODE ))   && install_node   || true
  (( WITH_GO ))     && install_go     || true
  (( WITH_RUST ))   && install_rust   || true
  (( WITH_DOCKER )) && install_docker || true
  (( WITH_LATEX ))  && install_latex  || true

  log "done"
}

main "$@"
