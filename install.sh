#!/usr/bin/env bash
#
# install.sh — single-command bootstrap for this dotfiles repo on Ubuntu/Debian
# or macOS. Idempotent: safe to re-run.
#
# Spec: docs/specs/active/2026-05-06-install-script.md
#
# Core (always run): system packages, zsh, submodules, symlinks,
# GitHub SSH auth + commit-signing keys.
# Optional modules (--with-*) are stubs in this task; filled in by Task 2.

set -euo pipefail
trap 'echo "FAILED at line $LINENO" >&2' ERR

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test seam: set TARGET_HOME to fully isolate every $HOME write (symlinks,
# ~/.claude, ~/.config, tool invocations). This is the ONLY supported way to
# test-run the installer — partial overrides (CLAUDE_DIR alone) leave
# link_one and friends writing into the real home.
if [[ -n "${TARGET_HOME:-}" ]]; then
  REAL_HOME="$HOME"
  export HOME="$TARGET_HOME"
else
  REAL_HOME="$HOME"
fi

ALLOW_FOREIGN_ROOT=0

# Canonical-root guard (runs in main() after arg parsing): a real-HOME
# install may only run from the canonical checkout. Running from a linked
# worktree or a scratch clone would repoint every home symlink at a
# directory that is about to be deleted (2026-08-06 incident: zshrc/nvim
# broke after a worktree test install). TARGET_HOME (isolated) and
# --allow-foreign-root both bypass.
guard_canonical_root() {
  [[ -n "${TARGET_HOME:-}" ]] && return 0
  (( ALLOW_FOREIGN_ROOT )) && return 0
  local canonical="$REAL_HOME/dotfiles"
  local root_real canon_real common_dir git_dir
  root_real="$(cd "$REPO_ROOT" && pwd -P)"
  canon_real="$(cd "$canonical" 2>/dev/null && pwd -P || true)"
  common_dir="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null || true)"
  git_dir="$(git -C "$REPO_ROOT" rev-parse --git-dir 2>/dev/null || true)"
  if [[ "$common_dir" != "$git_dir" ]]; then
    err "refusing to install into real HOME from a linked worktree: $REPO_ROOT"
    err "symlinks (~/.zshrc, ~/.config/nvim, ~/.config/tmux, …) would point at a disposable checkout."
    err "run from $canonical, or set TARGET_HOME=<dir> for an isolated test,"
    err "or pass --allow-foreign-root if you really mean it."
    exit 2
  fi
  if [[ -n "$canon_real" && "$root_real" != "$canon_real" ]]; then
    err "refusing to install into real HOME from non-canonical checkout: $root_real"
    err "canonical: $canon_real (expected for ~/.config/nvim and other symlink targets)."
    err "use TARGET_HOME=<dir> for an isolated test, or --allow-foreign-root."
    exit 2
  fi
}

DRY_RUN=0
NO_SYMLINK=0
WITH_NODE=0
WITH_GO=0
WITH_RUST=0
WITH_DOCKER=0
WITH_LATEX=0
WITH_CRG=0
WITH_PROJECTS=0
WITH_SECRETS=0
WITH_NVIM=0
WITH_CLAUDE_AGENTS=0
REGISTER_HOOKS=0
REGISTER_CURSOR=0
SYNC_CLAUDE_SETTINGS=0
SEED_SECRETS_MISSING=()  # (repo|KEY|service) tuples accumulated across run
PROJECTS_DIR="${DOTFILES_PROJECTS_DIR:-$HOME}"
PROJECT_NAMES=(llm-wiki stock-target-finder telegram-claude-bridge)
PROJECT_URLS=(
  https://github.com/ui-HookeyChiang/llm-wiki
  https://github.com/ui-HookeyChiang/stock-target-finder
  https://github.com/ui-HookeyChiang/telegram-claude-bridge
)
PROJECT_INSTALL=(repo-script repo-script npm)
# Parallel array: 1 if the project has git submodules (drives `git submodule
# update --init --recursive` post-clone). Source-of-truth lookup table — used
# in both real-run and --dry-run, so we don't need to probe `$dst/.gitmodules`
# (which doesn't exist in dry-run since the clone is simulated).
PROJECT_HAS_SUBMODULES=(1 0 0)

OS=""             # "linux" | "macos"
DISTRO_ID=""      # e.g. "ubuntu", "debian"
BACKUP_DIR=""     # lazily set on first symlink conflict
BACKUP_TS=""      # UTC timestamp captured once at start

# Whitelisted top-level dotfiles (live at $HOME/<name>).
DOTFILES=(
  .zshenv .zshrc .zprofile .vimrc .gitconfig .gitignore .inputrc
  .p10k.zsh .clang-format .clangd .ctags.sh
  .ai-commit.sh .ai-commit-msg.sh .tmux.reset.sh
  .git-completion.sh .git-prompt.sh .git_allowed_signers
)

# Whitelisted directory entries (live at $HOME/<name>).
DIRS=(
  .config/nvim
  .config/tmux
)

# Symlinks whose source and destination paths differ (unlike DOTFILES/DIRS,
# where dst mirrors src). Format: "src_in_dotfiles:dest_in_HOME". Must run
# AFTER init_submodules (sources/destinations may live inside a submodule's
# working tree; on first install the submodule's vanilla template is what gets
# backed up).
#
# .tmux.conf: tmux only auto-loads ~/.tmux.conf or ~/.config/tmux/tmux.conf
# (no leading dot); oh-my-tmux ships its entry file as .config/tmux/.tmux.conf
# (dotted), which tmux never finds on its own. Linking it to ~/.tmux.conf is
# what makes a fresh machine load the repo config at all.
#
# .tmux.conf.local: oh-my-tmux's .tmux.conf derives TMUX_CONF_LOCAL=
# "$TMUX_CONF.local" only when the variable is unset (.zshenv exports it to
# point at the repo file). This symlink keeps the canonical in-submodule path
# working as a fallback when tmux is started without that env var.
SUBMODULE_OVERRIDES=(
  ".config/tmux/.tmux.conf:.tmux.conf"
  ".tmux.conf.local:.config/tmux/.tmux.conf.local"
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

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

err() {
  printf 'ERROR: %s\n' "$*" >&2
}

# Submodule-specific recovery hint for init_submodules drift guard messages.
submodule_drift_hint() {
  case "$1" in
    .config/nvim)
      printf '%s' 'push from .config/nvim (topic branch off origin/dev), then bump the dotfiles gitlink'
      ;;
    .config/tmux)
      printf '%s' 'push from .config/tmux, then bump the dotfiles gitlink'
      ;;
    *)
      printf '%s' 'commit or push from the submodule, then bump the dotfiles gitlink'
      ;;
  esac
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
  - system packages (zsh, tmux, neovim, ripgrep, fd, fzf, bat, eza, jq, zoxide, git)
  - zsh as default shell (.zshrc auto-bootstraps zinit on first launch)
  - git submodules (.config/nvim, .config/tmux)
  - dotfile symlinks (whitelist + timestamped backup on conflict)
  - GitHub SSH key (~/.ssh/id_ed25519_github), Host github.com, allowed_signers,
    and gh upload as authentication + signing keys (fail-soft; never runs
    gh auth refresh)

Optional modules:
  --with-node     Node.js LTS + @anthropic-ai/claude-code (Task 2)
  --with-go       Go + golines (Task 2)
  --with-rust     rustup + stylua + rustfmt (Task 2)
  --with-docker   Docker Engine, Linux only (Task 2)
  --with-latex    MacTeX, macOS only (Task 2)
  --with-crg      code-review-graph (CRG) — persistent codebase graph for AI-assisted review.
                  Installs via pipx; writes per-repo .mcp.json on first use (run crg install).
                  Requires pipx (apt install pipx). Graph DB stored in .code-review-graph/ (gitignored).
  --with-projects Personal projects (llm-wiki, stock-target-finder, telegram-claude-bridge)
                  Auto-enables --with-node. Override clone dir with DOTFILES_PROJECTS_DIR (default: $HOME).
  --with-secrets  Materialize per-project .env from committed .env.tpl via macOS Keychain
                  (security find-generic-password). Auto-enables --with-projects. macOS only.
  --with-nvim     Install neovim LSP servers, formatters, treesitter parsers, and plugins
                  via headless bootstrap. Auto-enables --with-node, --with-go, --with-rust.
                  Runs healthcheck after install.
  --with-claude-agents
                  Delegate agent-harness install to skill-dev/install.sh:
                  skills fanout, agent definitions, hooks, docs/agents
                  config-doc symlinks, locked extras, OpenCode/Cursor config,
                  and post-install parity verification.
  --all           Enable all OS-compatible optional modules

Safety / testing:
  --allow-foreign-root    Override the canonical-root guard (real-HOME install
                           normally refuses to run from a linked worktree or
                           non-canonical checkout).
  TARGET_HOME=<dir>       Env var: fully isolate the run — every \$HOME write
                           (symlinks, ~/.claude, ~/.config) lands under <dir>.
                           The only supported way to test the installer.

Optional flags for --with-claude-agents:
  --register-hooks        Merge this repo's Claude/Codex/Cursor hooks into
                           settings.json / hooks.json (idempotent). Without
                           it, hooks are only symlinked.
  --sync-claude-settings   Merge .model into ~/.claude/settings.json.
  --register-cursor        Write .cursor/rules/*.mdc guardrails and merge
                           Cursor user-settings/cli-config templates.

Flags:
  --dry-run       Print actions, do not execute
  --no-symlink    Skip dotfile symlinking
  -h, --help      Show this help and exit

Environment (target-dir overrides, default to real paths; for testing):
  CLAUDE_DIR, OPENCODE_DIR, AGENTS_SKILLS_DIR
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
      --with-crg)     WITH_CRG=1 ;;
      --with-projects) WITH_PROJECTS=1 ;;
      --with-secrets) WITH_SECRETS=1 ;;
      --with-nvim)    WITH_NVIM=1 ;;
      --with-claude-agents) WITH_CLAUDE_AGENTS=1 ;;
      --allow-foreign-root) ALLOW_FOREIGN_ROOT=1 ;;
      --register-hooks)     REGISTER_HOOKS=1 ;;
      --register-cursor)    REGISTER_CURSOR=1 ;;
      --sync-claude-settings) SYNC_CLAUDE_SETTINGS=1 ;;
      --all)
        WITH_NODE=1
        WITH_GO=1
        WITH_RUST=1
        WITH_DOCKER=1
        WITH_LATEX=1
        WITH_CRG=1
        WITH_PROJECTS=1
        WITH_SECRETS=1
        WITH_NVIM=1
        WITH_CLAUDE_AGENTS=1
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

  # Auto-flip WITH_PROJECTS when WITH_SECRETS is set (need projects cloned to seed .env into).
  if (( WITH_SECRETS )) && (( ! WITH_PROJECTS )); then
    WITH_PROJECTS=1
    note "--with-secrets auto-enabled --with-projects (need projects to seed .env into)"
  fi

  # Auto-flip WITH_NODE when WITH_PROJECTS is set (telegram-claude-bridge needs npm).
  if (( WITH_PROJECTS )) && (( ! WITH_NODE )); then
    WITH_NODE=1
    note "--with-projects auto-enabled --with-node (telegram-claude-bridge needs npm)"
  fi

  # Auto-flip language toolchains when WITH_NVIM is set (LSP servers need them).
  if (( WITH_NVIM )); then
    if (( ! WITH_NODE )); then
      WITH_NODE=1
      note "--with-nvim auto-enabled --with-node (tsls needs node)"
    fi
    if (( ! WITH_GO )); then
      WITH_GO=1
      note "--with-nvim auto-enabled --with-go (gopls needs go)"
    fi
    if (( ! WITH_RUST )); then
      WITH_RUST=1
      note "--with-nvim auto-enabled --with-rust (rust-analyzer + stylua need cargo)"
    fi
  fi
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
  # A NOPASSWD sudoers rule may permit commands in a non-interactive runner
  # while still rejecting `sudo -v` because no terminal is attached.
  if ! sudo -n true 2>/dev/null; then
    sudo -v
  fi
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

# Map apt package name -> space-separated binary names that count as "present".
# Used by is_present_apt so install_core_packages skips packages whose binary
# is already in PATH (e.g. nvim built from PPA/source, not tracked by dpkg).
# Packages not listed default to "binary name == pkg name".
#
# Linux-only guard: `declare -A` (associative array) requires bash 4.0+, but
# macOS ships /bin/bash 3.2 (Apple GPLv3 freeze). Under bash 3.2 this line is
# parsed as an indexed array and `[neovim]` becomes an arithmetic expression,
# evaluating `neovim` as a variable — which under `set -u` (line 11) aborts
# the script at load time, before detect_os runs. is_present_apt is only
# called on the apt path, so guarding both the array and the function on
# Linux keeps macOS load-time clean without rewriting either.
# `$OS` is not set yet at this point (detect_os runs at line 907), so we
# probe `uname -s` directly.
if [[ "$(uname -s)" == "Linux" ]]; then
  declare -A PKG_BINARIES=(
    [neovim]="nvim"
    [ripgrep]="rg"
    [fd-find]="fdfind fd"
    [bat]="batcat bat"
  )

  # is_present_apt <pkg>
  # Returns 0 if installed via apt OR any of its known binaries is in PATH.
  is_present_apt() {
    local pkg="$1"
    if is_installed_apt "$pkg"; then
      return 0
    fi
    local bins="${PKG_BINARIES[$pkg]:-$pkg}"
    local b
    for b in $bins; do
      if command -v "$b" >/dev/null 2>&1; then
        return 0
      fi
    done
    return 1
  }
fi

# is_installed_brew <pkg>
is_installed_brew() {
  brew list --formula "$1" >/dev/null 2>&1
}

install_core_packages() {
  log "install_core_packages"
  local pkgs
  case "$OS" in
    linux)
      pkgs=(zsh tmux neovim ripgrep fd-find fzf bat eza jq zoxide git)
      local missing=()
      for p in "${pkgs[@]}"; do
        if is_present_apt "$p"; then
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
      pkgs=(zsh tmux neovim ripgrep fd fzf bat eza jq zoxide git)
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

  # Drift guard: `git submodule update` detach-resets each submodule to the
  # recorded gitlink, silently discarding local commits made inside the
  # submodule. For every INITIALIZED submodule whose HEAD is not reachable
  # from the recorded pointer, warn and exclude it; update the rest per-path.
  # Uninitialized submodules always init normally.
  local update_paths=() entry path recorded head
  # -z output is "<key>\n<value>\0" per record: NUL-safe parsing keeps
  # submodule paths containing whitespace intact (submodule NAMES may also
  # contain spaces, so splitting the one-line form on spaces is not enough).
  while IFS= read -r -d '' entry; do
    path="${entry#*$'\n'}"
    [[ -n "$path" ]] || continue
    if [[ ! -e "$REPO_ROOT/$path/.git" ]]; then
      update_paths+=("$path")  # uninitialized: --init handles it
      continue
    fi
    recorded="$(git -C "$REPO_ROOT" rev-parse ":$path" 2>/dev/null)" || {
      update_paths+=("$path"); continue; }
    head="$(git -C "$REPO_ROOT/$path" rev-parse HEAD 2>/dev/null)" || {
      update_paths+=("$path"); continue; }
    # Recorded commit absent locally (submodule behind a fetch): fetch, then
    # re-check, so the ancestry test below runs on real objects — otherwise a
    # drifted submodule whose recorded SHA is unfetched would be included and
    # detach-reset, losing the local commits this guard exists to protect.
    if ! git -C "$REPO_ROOT/$path" cat-file -e "$recorded^{commit}" 2>/dev/null; then
      git -C "$REPO_ROOT/$path" fetch --quiet >/dev/null 2>&1 || true
    fi
    if ! git -C "$REPO_ROOT/$path" cat-file -e "$recorded^{commit}" 2>/dev/null; then
      warn "submodule $path: dotfiles pin $recorded not available locally even after fetch; skipping update (check submodule remote access, then re-run)"
      continue
    fi
    if ! git -C "$REPO_ROOT/$path" merge-base --is-ancestor "$head" "$recorded" 2>/dev/null; then
      warn "submodule $path: HEAD $head is ahead of dotfiles pin $recorded; skipping update ($(submodule_drift_hint "$path"))"
      continue
    fi
    update_paths+=("$path")
  done < <(git config -f "$REPO_ROOT/.gitmodules" -z --get-regexp '^submodule\..*\.path$')

  if (( ${#update_paths[@]} == 0 )); then
    warn "all submodules skipped by drift guard; nothing to update (resolve warnings above, then re-run install.sh)"
    return 0
  fi
  # LIMITATION: --recursive still detach-resets NESTED submodules without a
  # drift check — the guard above inspects top-level paths only. No nested
  # submodules exist in this repo today; revisit if one is ever added.
  run git -C "$REPO_ROOT" submodule update --init --recursive -- "${update_paths[@]}"
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
    # `-e "$dst"` follows the symlink: false when $dst dangles (e.g. points into a
    # removed worktree under $REPO_ROOT/.worktrees/...), so we fall through to repair.
    if { [[ "$target" == "$src" ]] || [[ "$target" == "$REPO_ROOT/"* ]]; } \
       && [[ -e "$src" ]] && [[ -e "$dst" ]]; then
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

# link_submodule_override <src_rel>:<dst_rel>
#
# Mirrors link_one's file/symlink/missing branching, but the destination is
# decoupled from the source path: src lives at $REPO_ROOT/$src_rel and dst lives
# at $HOME/$dst_rel (typically inside a submodule's working tree like
# ~/.config/tmux/.tmux.conf.local). The submodule's own loader then picks up
# our override at the canonical path it expects.
#
# Branch behaviour (matches link_one):
#   - missing dst: ln -s
#   - existing symlink into $REPO_ROOT (resolves): skip (idempotent)
#   - existing symlink elsewhere or dangling: backup + re-link
#   - existing regular file (the submodule's vanilla template on first install):
#     backup + re-link
link_submodule_override() {
  local entry="$1"
  local src_rel="${entry%%:*}"
  local dst_rel="${entry#*:}"
  local src="$REPO_ROOT/$src_rel"
  local dst="$HOME/$dst_rel"

  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    note "skip $src_rel -> $dst_rel (src not in repo)"
    return 0
  fi

  # Ensure parent dir of $dst exists (matches link_one).
  local parent
  parent="$(dirname "$dst")"
  if [ ! -d "$parent" ]; then
    run mkdir -p "$parent"
  fi

  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    # Branch 1: target missing.
    note "link submodule override $src_rel -> $dst"
    run ln -s "$src" "$dst"
    return 0
  fi

  if [ -L "$dst" ]; then
    local target
    target="$(readlink "$dst")"
    # Already points into the repo AND resolves: idempotent skip.
    case "$target" in
      "$src"|"$REPO_ROOT"/*)
        if [ -e "$src" ] && [ -e "$dst" ]; then
          note "skip $src_rel -> $dst (already linked)"
          return 0
        fi
        ;;
    esac
    # Foreign or dangling: back up and re-link.
    ensure_backup_dir
    note "backup foreign symlink $dst -> $target"
    run mkdir -p "$BACKUP_DIR/$(dirname "$dst_rel")"
    run mv "$dst" "$BACKUP_DIR/$dst_rel"
    run ln -s "$src" "$dst"
    return 0
  fi

  # Branch 3: regular file (typically the submodule's vanilla template).
  ensure_backup_dir
  note "backup $dst -> $BACKUP_DIR/$dst_rel"
  run mkdir -p "$BACKUP_DIR/$(dirname "$dst_rel")"
  run mv "$dst" "$BACKUP_DIR/$dst_rel"
  run ln -s "$src" "$dst"
}

symlink_submodule_overrides() {
  log "symlink_submodule_overrides"
  if (( NO_SYMLINK )); then
    note "--no-symlink set; skip"
    return 0
  fi
  local entry
  for entry in "${SUBMODULE_OVERRIDES[@]}"; do
    link_submodule_override "$entry"
  done

  # Cleanup the old dead symlink left over from the previous install layout
  # ($HOME/.tmux.conf.local pointed into $REPO_ROOT but was never read by tmux
  # because oh-my-tmux overrides TMUX_CONF_LOCAL at startup). Conservative:
  # only touch it when it's a symlink whose target is inside $REPO_ROOT. If
  # the user has hand-managed file or a symlink pointing elsewhere, leave it.
  if [ -L "$HOME/.tmux.conf.local" ]; then
    local target
    target="$(readlink "$HOME/.tmux.conf.local")"
    case "$target" in
      "$REPO_ROOT"/*)
        note "removing stale symlink $HOME/.tmux.conf.local (target $target)"
        run rm "$HOME/.tmux.conf.local"
        ;;
    esac
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
  # The npm package @anthropic-ai/claude-code installs a binary named `claude`,
  # not `claude-code`. Probe via the npm global registry for an accurate skip.
  if npm ls -g --depth=0 @anthropic-ai/claude-code >/dev/null 2>&1; then
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

install_nvim_deps() {
  log "install_nvim_deps"

  # Ensure ~/.local/bin exists (nvim init.lua prepends it to PATH)
  run mkdir -p "$HOME/.local/bin"

  # --- LSP servers -----------------------------------------------------------
  # basedpyright + ruff (Python LSP + linter-as-LSP)
  if command -v basedpyright >/dev/null 2>&1; then
    note "skip basedpyright (installed)"
  else
    note "installing basedpyright via npm"
    run npm install -g basedpyright
  fi
  if command -v ruff >/dev/null 2>&1; then
    note "skip ruff (installed)"
  else
    note "installing ruff via pip/pipx"
    if command -v pipx >/dev/null 2>&1; then
      run pipx install ruff
    else
      run pip3 install --user ruff
      # Symlink into ~/.local/bin so nvim (and shell) can find it
      local ruff_bin
      ruff_bin="$(python3 -m site --user-base 2>/dev/null)/bin/ruff"
      if [[ -x "$ruff_bin" ]] && [[ ! -e "$HOME/.local/bin/ruff" ]]; then
        run ln -sf "$ruff_bin" "$HOME/.local/bin/ruff"
      fi
    fi
  fi

  # lua-language-server
  if command -v lua-language-server >/dev/null 2>&1; then
    note "skip lua-language-server (installed)"
  else
    case "$OS" in
      macos) run brew install lua-language-server ;;
      linux)
        note "installing lua-language-server via GitHub release"
        local luals_ver
        luals_ver="$(curl -fsSL https://api.github.com/repos/LuaLS/lua-language-server/releases/latest | jq -r .tag_name)"
        local luals_dir="$HOME/.local/lib/lua-language-server"
        run mkdir -p "$luals_dir"
        run bash -c "curl -fsSL 'https://github.com/LuaLS/lua-language-server/releases/download/${luals_ver}/lua-language-server-${luals_ver}-linux-x64.tar.gz' | tar xz -C '$luals_dir'"
        run ln -sf "$luals_dir/bin/lua-language-server" "$HOME/.local/bin/lua-language-server"
        ;;
    esac
  fi

  # clangd (usually installed with clang or llvm)
  if command -v clangd >/dev/null 2>&1; then
    note "skip clangd (installed)"
  else
    case "$OS" in
      macos) run brew install llvm ;; # provides clangd
      linux) run sudo apt-get install -y clangd ;;
    esac
  fi

  # cmake-language-server
  if command -v cmake-language-server >/dev/null 2>&1; then
    note "skip cmake-language-server (installed)"
  else
    note "installing cmake-language-server via pip"
    if command -v pipx >/dev/null 2>&1; then
      run pipx install cmake-language-server
    else
      run pip3 install --user cmake-language-server
      # Symlink into ~/.local/bin
      local cms_bin
      cms_bin="$(python3 -m site --user-base 2>/dev/null)/bin/cmake-language-server"
      if [[ -x "$cms_bin" ]] && [[ ! -e "$HOME/.local/bin/cmake-language-server" ]]; then
        run ln -sf "$cms_bin" "$HOME/.local/bin/cmake-language-server"
      fi
    fi
  fi

  # typescript-language-server (tsls)
  if command -v typescript-language-server >/dev/null 2>&1; then
    note "skip typescript-language-server (installed)"
  else
    note "installing typescript-language-server via npm"
    run npm install -g typescript typescript-language-server
  fi

  # gopls (Go LSP — install via go install, go must be on PATH from install_go)
  if command -v gopls >/dev/null 2>&1; then
    note "skip gopls (installed)"
  else
    note "installing gopls via go install"
    run go install golang.org/x/tools/gopls@latest
  fi

  # rust-analyzer (via rustup component — install_rust ensures rustup exists)
  if command -v rust-analyzer >/dev/null 2>&1; then
    note "skip rust-analyzer (installed)"
  else
    note "installing rust-analyzer via rustup"
    run rustup component add rust-analyzer
  fi

  # zls (Zig Language Server)
  if command -v zls >/dev/null 2>&1; then
    note "skip zls (installed)"
  else
    case "$OS" in
      macos)
        if is_installed_brew zls; then
          note "skip zls (brew formula present)"
        else
          note "installing zls via brew"
          run brew install zls
        fi
        ;;
      linux)
        note "installing zls — see https://github.com/zigtools/zls/releases"
        note "  (manual: download binary to ~/.local/bin/zls)"
        ;;
    esac
  fi

  # --- Formatters (not covered by language toolchains) -----------------------
  # clang-format (often bundled with clangd/llvm, but verify)
  if ! command -v clang-format >/dev/null 2>&1; then
    case "$OS" in
      macos) : ;; # already installed via llvm above or Xcode
      linux) run sudo apt-get install -y clang-format ;;
    esac
  fi

  # prettier (JS/TS formatter — via npm)
  if command -v prettier >/dev/null 2>&1; then
    note "skip prettier (installed)"
  else
    note "installing prettier via npm"
    run npm install -g prettier
  fi

  # --- Treesitter parsers ----------------------------------------------------
  # TSInstallSync requires treesitter plugin to be loaded. On a fresh install the
  # plugin may not be available yet (vim.pack hasn't run). Bootstrap plugins first,
  # then install parsers. Use a deferred lua call to handle nightly-only init.lua
  # options that may error in headless mode.
  note "bootstrapping vim.pack plugins (headless)"
  # vim.pack downloads plugins on first startup when confirm=false.
  # Give it up to 60s to clone all repos then quit.
  run timeout 90 nvim --headless +"lua vim.defer_fn(function() vim.cmd('qa!') end, 60000)" 2>/dev/null || true

  note "installing treesitter parsers (headless)"
  run timeout 120 nvim --headless +"lua vim.defer_fn(function() pcall(vim.cmd, 'TSInstallSync c cpp rust zig lua python proto typescript javascript tsx css scss diff dockerfile graphql html sql markdown markdown_inline vimdoc vim cmake'); vim.defer_fn(function() vim.cmd('qa!') end, 5000) end, 5000)" 2>/dev/null || true

  # --- Healthcheck -----------------------------------------------------------
  note "running nvim healthcheck"
  if ! (( DRY_RUN )); then
    nvim --headless +'checkhealth lsp treesitter' +'w! /tmp/nvim-healthcheck.txt' +qa 2>/dev/null || true
    if grep -qi 'ERROR' /tmp/nvim-healthcheck.txt 2>/dev/null; then
      note "healthcheck found issues — review /tmp/nvim-healthcheck.txt"
    else
      note "healthcheck passed"
    fi
  fi
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
  local docker_distro=""
  case " $DISTRO_ID " in
    *ubuntu*) docker_distro="ubuntu" ;;
    *debian*) docker_distro="debian" ;;
    *)        err "install_docker: unsupported distro '$DISTRO_ID'; expected ubuntu or debian"; return 1 ;;
  esac
  run sudo install -m 0755 -d /etc/apt/keyrings
  run sudo curl -fsSL "https://download.docker.com/linux/${docker_distro}/gpg" -o /etc/apt/keyrings/docker.asc
  run sudo chmod a+r /etc/apt/keyrings/docker.asc
  run bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${docker_distro} \$(. /etc/os-release && echo \\\"\$VERSION_CODENAME\\\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null"
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
# Claude/OpenCode/Cursor agent-harness parity
# ---------------------------------------------------------------------------
# Reproduces skill-dev install.sh's effects for Claude Code, OpenCode, and
# Cursor. Skills are relative symlinks into the skill-dev submodule
# (single source of truth); hooks remain real copies registered by path.
# A skill-dev checkout outside this repo is still not required — but the
# submodule must be initialized before the fanout, or every skill entry is
# a dangling symlink and the fanout silently installs nothing (guarded in
# ensure_skill_dev_submodule + a dangling check in the fanout loop).
#
# Target-dir overrides (fake-HOME testability; default to real paths):
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
OPENCODE_DIR="${OPENCODE_DIR:-$HOME/.config/opencode}"
AGENTS_SKILLS_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
# Cursor has no file-based user-level instruction surface; project-level
# .cursor/rules/ in the checkout is the closest equivalent (matches
# skill-dev install.sh's own $REPO_ROOT/.cursor/rules default — these files
# are meant to be committed, same as skill-dev's own tracked .cursor/rules/).
# Override only for test-seam isolation (fake-HOME runs must never write into
# the real checkout).

# SKILLDEV: the skill-dev submodule — canonical source for skills, hooks,
# scripts, _shared, and user-global config (.claude/: CLAUDE.md, docs/,
# settings.json, lock manifests).
SKILLDEV="$REPO_ROOT/skill-dev"

# ensure_skill_dev_submodule: everything below sources from the skill-dev
# submodule.
# On a fresh clone the submodule dir is empty and the whole section would
# no-op — init it first. Idempotent; requires network only when missing.
ensure_skill_dev_submodule() {
  [[ -f "$REPO_ROOT/.gitmodules" ]] || return 0
  [[ -f "$SKILLDEV/.claude/CLAUDE.md" ]] && return 0
  note "initializing skill-dev submodule (skills/hooks/config source)"
  if ! run git -C "$REPO_ROOT" submodule update --init -- skill-dev; then
    note "WARN: skill-dev submodule init failed — agent-harness install will no-op"
    return 0
  fi
}

# _dc_ensure_symlink SRC DST: absent-only symlink (never replaces anything);
# mirrors link_one's foreign-symlink/real-file backup branches so a prior
# real install isn't clobbered.
_dc_ensure_symlink() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    local target
    target="$(readlink "$dst")"
    if [[ "$target" == "$src" ]]; then
      note "skip $(basename "$dst") (already linked)"
      return 0
    fi
    ensure_backup_dir
    note "backup foreign symlink $dst -> $target"
    run mkdir -p "$(dirname "$BACKUP_DIR/${dst#"$HOME"/}")"
    run mv "$dst" "$BACKUP_DIR/${dst#"$HOME"/}"
    run ln -s "$src" "$dst"
    return 0
  fi
  if [[ -e "$dst" ]]; then
    ensure_backup_dir
    note "backup $dst -> $BACKUP_DIR/${dst#"$HOME"/}"
    run mkdir -p "$(dirname "$BACKUP_DIR/${dst#"$HOME"/}")"
    run mv "$dst" "$BACKUP_DIR/${dst#"$HOME"/}"
    run ln -s "$src" "$dst"
    return 0
  fi
  run ln -s "$src" "$dst"
  note "linked $(basename "$dst")"
}

# install_claude_agents — delegate to skill-dev/install.sh for skills fanout,
# agent definitions, hook symlinks + registration, config-doc symlinks,
# OpenCode config, Cursor rules, and locked extras.
# Only _shared sibling symlinks remain here (skill-dev denylists _shared
# during fanout, but installed skills resolve ../../_shared relative to
# their symlink location).
install_claude_agents() {
  log "install_claude_agents"

  ensure_skill_dev_submodule

  # Delegate to skill-dev/install.sh (PHASE 2-7).
  if [[ -x "$SKILLDEV/install.sh" || -f "$SKILLDEV/install.sh" ]]; then
    local sd_args=(--skip-bins)
    (( REGISTER_HOOKS )) && sd_args+=(--register-hooks)
    (( REGISTER_CURSOR )) && sd_args+=(--register-cursor)
    (( SYNC_CLAUDE_SETTINGS )) && sd_args+=(--sync-settings)
    (( DRY_RUN )) && sd_args+=(--dry-run)
    note "delegating to skill-dev/install.sh ${sd_args[*]}"
    SKILL_INSTALL_ALLOW_WORKTREE=1 bash "$SKILLDEV/install.sh" "${sd_args[@]}" \
      || note "WARN: skill-dev/install.sh reported a problem (continuing)"
  else
    note "WARN: skill-dev/install.sh not found; skipping agent-harness install"
    return 0
  fi

  # _shared sibling symlinks: skill-dev denylists _shared during PHASE 2
  # fanout, but installed skill scripts resolve ../../_shared relative to
  # their symlink location — each target needs a _shared sibling.
  local skills_targets=("$CLAUDE_DIR/skills")
  command -v opencode >/dev/null 2>&1 && skills_targets+=("$OPENCODE_DIR/skills")
  { command -v codex >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1; } \
    && skills_targets+=("$AGENTS_SKILLS_DIR")

  local t
  for t in "${skills_targets[@]}"; do
    [[ -d "$t" ]] && _dc_ensure_symlink "$SKILLDEV/_shared" "$t/_shared"
  done
  _dc_ensure_symlink "$SKILLDEV/_shared" "$CLAUDE_DIR/_shared"
}

# verify_claude_parity — point 9: post-install agent-compat check via the
# snapshot's check-compat.sh, and a skills-lock verify pass. Non-zero exit
# prints warnings but never aborts install (matches skill-dev behavior).
verify_claude_parity() {
  log "verify_claude_parity"
  local parity_script="$SKILLDEV/agent-compat/scripts/check-compat.sh"
  if [[ -x "$parity_script" ]] || [[ -f "$parity_script" ]]; then
    local parity_json parity_status
    set +e
    parity_json="$(HOME="$HOME" bash "$parity_script" --format json 2>/dev/null)"
    parity_status=$?
    set -e
    if [[ "$parity_status" -eq 0 || "$parity_status" -eq 1 ]] && command -v jq >/dev/null 2>&1; then
      local gaps warnings
      gaps="$(printf '%s' "$parity_json" | jq -r '.counts.gaps // 0' 2>/dev/null || echo 0)"
      warnings="$(printf '%s' "$parity_json" | jq -r '.counts.warnings // 0' 2>/dev/null || echo 0)"
      note "agent-compat: $gaps gap(s), $warnings warning(s)"
    else
      note "agent-compat check did not run cleanly (exit $parity_status); continuing"
    fi
  fi
  if [[ -x "$SKILLDEV/scripts/skills-lock.sh" ]] || [[ -f "$SKILLDEV/scripts/skills-lock.sh" ]]; then
    SKILLS_LOCK_FILE="$SKILLDEV/skills-lock.json" SKILLS_LOCK_SKILLS_ROOT="$AGENTS_SKILLS_DIR" \
      bash "$SKILLDEV/scripts/skills-lock.sh" verify \
      || note "WARN: skills-lock verify failed (non-fatal)"
  fi
}

install_crg() {
  log "install_crg"
  # Ensure pipx is available.
  if ! command -v pipx >/dev/null 2>&1; then
    case "$OS" in
      linux)
        note "installing pipx via apt"
        run sudo apt-get install -y pipx
        run python3 -m pipx ensurepath
        ;;
      macos)
        if is_installed_brew pipx; then
          note "skip pipx (brew formula present)"
        else
          note "installing pipx via brew"
          run brew install pipx
          run pipx ensurepath
        fi
        ;;
    esac
  else
    note "skip pipx (installed: $(pipx --version 2>/dev/null || echo present))"
  fi

  # Install code-review-graph via pipx (idempotent).
  if pipx list 2>/dev/null | grep -q 'code-review-graph'; then
    note "skip code-review-graph (already installed via pipx)"
  else
    note "installing code-review-graph via pipx"
    run pipx install code-review-graph
  fi
}

# seed_env <envfile> <example>
# If $envfile already exists: leave as-is. Otherwise cp $example -> $envfile and
# rewrite each KEY=VALUE line so VALUE becomes FIXME-PLEASE-FILL. Comments
# (lines starting with optional whitespace then '#') and blank lines pass
# through untouched. Trailing inline comments (KEY=val # comment) are NOT
# preserved — the whole RHS becomes FIXME-PLEASE-FILL.
#
# Uses the BSD-awk-portable temp-file pattern (NOT GNU `awk -i inplace`).
seed_env() {
  local envfile="$1"
  local example="$2"
  if [[ -f "$envfile" ]]; then
    note "$(basename "$(dirname "$envfile")")/.env present, leaving as-is"
    return 0
  fi
  if (( DRY_RUN )); then
    printf '+ cp %q %q && awk-rewrite %q\n' "$example" "$envfile" "$envfile" >&2
    return 0
  fi
  cp "$example" "$envfile"
  local tmpfile
  tmpfile="$(mktemp "${envfile}.XXXXXX")"
  awk '/^[[:space:]]*#/ || /^[[:space:]]*$/ {print; next}
       /=/ {sub(/=.*/,"=FIXME-PLEASE-FILL"); print; next}
       {print}' "$envfile" > "$tmpfile" && mv "$tmpfile" "$envfile"
  chmod 600 "$envfile" 2>/dev/null || note "$(basename "$(dirname "$envfile")")/.env: chmod 600 failed (FS may not support; default umask used)"
  note "created $envfile from .env.example with FIXME-PLEASE-FILL sentinels — fill in before first run"
}

# seed_one_env_tpl <repo-name> <tpl-path> <env-path>
# Per-line strict matcher (S10): comment/blank, security cmd substitution, literal.
# Pattern 4 (unrecognized) fail-soft pass-through with note. Dry-run extracts
# `-s <service>` tokens via awk match() — does NOT call security.
# Resolved values use `security find-generic-password -s <service> -a $USER -w`.
# Misses: write KEY= and append (repo|KEY|service) to global SEED_SECRETS_MISSING.
seed_one_env_tpl() {
  local repo="$1" tpl="$2" env="$3"

  if [[ "$OS" != "macos" ]]; then
    note "skip $repo .env.tpl (Keychain is macOS-only)"
    return 0
  fi

  if [[ ! -f "$tpl" ]]; then
    note "skip $repo (no .env.tpl)"
    return 0
  fi

  if (( DRY_RUN )); then
    # Static parse of -s <service> tokens via bash regex (BSD-awk-portable);
    # do NOT call security.
    local services="" line svc
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ -s[[:space:]]+([^[:space:]]+)[[:space:]]+-w ]]; then
        svc="${BASH_REMATCH[1]}"
        services+="${services:+, }$svc"
      fi
    done < "$tpl"
    if [[ -n "$services" ]]; then
      note "+ would inject from $repo/.env.tpl using keychain entries: $services"
    else
      note "+ would inject from $repo/.env.tpl (no keychain lookups detected)"
    fi
    return 0
  fi

  if [[ -f "$env" ]]; then
    note "$repo/.env present, leaving as-is"
    return 0
  fi

  local tmp
  tmp="$(mktemp "${env}.XXXXXX")"

  local lineno=0 line key service val
  local local_missing=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    # Pattern 1: comment or blank.
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi
    # Pattern 2: KEY=$(security find-generic-password -s <service> -w)
    if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=\$\(security[[:space:]]+find-generic-password[[:space:]]+-s[[:space:]]+([^[:space:]]+)[[:space:]]+-w\)$ ]]; then
      key="${BASH_REMATCH[1]}"
      service="${BASH_REMATCH[2]}"
      if val="$(security find-generic-password -s "$service" -a "$USER" -w 2>/dev/null)"; then
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
      else
        printf '%s=\n' "$key" >> "$tmp"
        local_missing=$((local_missing + 1))
        SEED_SECRETS_MISSING+=("$repo|$key|$service")
      fi
      continue
    fi
    # Pattern 3: KEY=<literal> (no command substitution).
    if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*=[^$\(]*$ ]]; then
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi
    # Pattern 4: unrecognized — pass through with note.
    note "$repo/.env.tpl line $lineno has unrecognized shape, passing through as-is"
    printf '%s\n' "$line" >> "$tmp"
  done < "$tpl"

  mv "$tmp" "$env"
  chmod 600 "$env" 2>/dev/null || note "$repo/.env: chmod 600 failed (FS may not support; default umask used)"

  if (( local_missing > 0 )); then
    note "$repo/.env created with $local_missing missing keychain entries (see end-of-run block)"
  else
    note "$repo/.env created from .env.tpl, all keychain entries resolved"
  fi
}

# seed_secrets — end-of-run reporter. macOS-only. Prints copy-pasteable
# `security add-generic-password` lines for accumulated misses.
seed_secrets() {
  log "seed_secrets"
  if [[ "$OS" != "macos" ]]; then
    note "Keychain is macOS-only; skipping bootstrap-block reporter"
    return 0
  fi
  if (( ${#SEED_SECRETS_MISSING[@]} == 0 )); then
    note "all keychain entries resolved (or no .env.tpl files processed)"
    return 0
  fi
  err "missing keychain entries — add them to populate .env on next run:"
  err "(after adding, run: rm <repo>/.env && ./install.sh --with-secrets)"
  local entry repo key service
  for entry in "${SEED_SECRETS_MISSING[@]}"; do
    IFS='|' read -r repo key service <<< "$entry"
    printf "security add-generic-password -s %q -a %q -w 'YOUR_VALUE_HERE'  # %s/%s\n" \
      "$service" "$USER" "$repo" "$key" >&2
  done
}

# install_one_project <name> <url> <method> <dst> <has_submodules>
#
# In --dry-run mode the clone is simulated, so $dst doesn't actually exist on
# disk. Filesystem probes (`-f $dst/install.sh`, `-f $dst/.gitmodules`,
# `-f $dst/.env.example`) would all fail and produce misleading errors. We
# therefore trust the dispatch table (`method`, `has_submodules`) under
# DRY_RUN and only probe the filesystem on a real run.
install_one_project() {
  local name="$1" url="$2" method="$3" dst="$4" has_submodules="$5"

  # 1. Clone (idempotent).
  if [[ -d "$dst/.git" ]]; then
    note "skip clone $name (already cloned at $dst)"
  else
    note "cloning $name -> $dst"
    run git clone "$url" "$dst"
  fi

  # 2. Submodules (idempotent: no-op if all initialized).
  # Trust the dispatch table — works for both dry-run and real-run.
  if (( has_submodules )); then
    run git -C "$dst" submodule update --init --recursive
  fi

  # 3. Install dispatch.
  case "$method" in
    repo-script)
      if (( DRY_RUN )); then
        note "would run $name/install.sh"
        run bash -c "cd '$dst' && bash install.sh"
      elif [[ -f "$dst/install.sh" ]]; then
        note "running $name/install.sh"
        run bash -c "cd '$dst' && bash install.sh"
      else
        err "$name expected install.sh but none found"
        return 1
      fi
      ;;
    npm)
      if (( DRY_RUN )); then
        note "would run npm install in $name"
        run bash -c "cd '$dst' && npm install"
      elif ! command -v npm >/dev/null 2>&1; then
        err "$name needs npm but it's not on PATH (was --with-node skipped or did install_node fail?)"
        return 1
      elif [[ -d "$dst/node_modules" ]]; then
        note "skip $name npm install (node_modules present)"
      else
        note "running npm install in $name"
        run bash -c "cd '$dst' && npm install"
      fi
      ;;
    *)
      err "$name has unknown install method: $method"
      return 1
      ;;
  esac

  # 4. .env seed (S4 cascade: existing .env wins; .env.tpl beats .env.example).
  # In dry-run we can't know whether .env.tpl/.env.example exist; both helpers
  # short-circuit cleanly under DRY_RUN. F2: dry-run prints both branches.
  if (( DRY_RUN )); then
    if (( WITH_SECRETS )); then
      seed_one_env_tpl "$name" "$dst/.env.tpl" "$dst/.env"
    fi
    seed_env "$dst/.env" "$dst/.env.example"
  elif [[ -f "$dst/.env" ]]; then
    note "$name/.env present, leaving as-is"
  elif (( WITH_SECRETS )) && [[ -f "$dst/.env.tpl" ]]; then
    seed_one_env_tpl "$name" "$dst/.env.tpl" "$dst/.env"
  elif [[ -f "$dst/.env.example" ]]; then
    seed_env "$dst/.env" "$dst/.env.example"
  fi
}

install_projects() {
  log "install_projects"
  note "PROJECTS_DIR=$PROJECTS_DIR"
  if [[ ! -d "$PROJECTS_DIR" ]]; then
    note "creating $PROJECTS_DIR"
    run mkdir -p "$PROJECTS_DIR"
  fi

  local failures=()
  local i name url method has_submodules dst
  for i in "${!PROJECT_NAMES[@]}"; do
    name="${PROJECT_NAMES[$i]}"
    url="${PROJECT_URLS[$i]}"
    method="${PROJECT_INSTALL[$i]}"
    has_submodules="${PROJECT_HAS_SUBMODULES[$i]}"
    dst="$PROJECTS_DIR/$name"

    if ! ( install_one_project "$name" "$url" "$method" "$dst" "$has_submodules" ); then
      err "$name install failed (continuing)"
      failures+=("$name")
    fi
  done

  if (( ${#failures[@]} > 0 )); then
    err "failed: ${failures[*]} (installed $((${#PROJECT_NAMES[@]} - ${#failures[@]}))/${#PROJECT_NAMES[@]})"
    return 1
  fi
  note "installed all: ${PROJECT_NAMES[*]}"
}

# ---------------------------------------------------------------------------
# GitHub SSH auth + commit signing
# ---------------------------------------------------------------------------
# Matches .gitconfig: gpg.format=ssh, user.signingkey=~/.ssh/id_ed25519_github.pub
# Remote upload uses gh ssh-key add. Does not run `gh auth refresh` (browser).
# Skip GitHub API when HOME != REAL_HOME (TARGET_HOME and unit tests).

_github_ssh_print_sop() {
  local pub="$1" host_id="$2"
  note "SOP: gh auth login   # if needed"
  note "SOP: gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key"
  note "SOP: gh ssh-key add $pub --title $host_id --type authentication"
  note "SOP: gh ssh-key add $pub --title signing-${host_id} --type signing"
}

_github_ssh_ensure_uploaded() {
  local pub="$1" list="$2" blob="$3" kind="$4" title="$5"
  if printf '%s\n' "$list" | grep -F "$blob" | grep -qE "${kind}$"; then
    note "skip GitHub $kind key (already registered)"
    return 0
  fi
  if gh ssh-key add "$pub" --title "$title" --type "$kind"; then
    note "registered GitHub $kind key ($title)"
    return 0
  fi
  note "gh ssh-key add --type $kind failed"
  return 1
}

setup_github_ssh_signing() {
  log "setup_github_ssh_signing"

  local key="$HOME/.ssh/id_ed25519_github"
  local pub="${key}.pub"
  local ssh_config="$HOME/.ssh/config"
  local signers="$HOME/.git_allowed_signers"
  local email="hookey.chiang@gmail.com"
  local host_id algo blob
  host_id="$(hostname -s 2>/dev/null || hostname)"

  run mkdir -p "$HOME/.ssh"
  if [[ -f "$key" && -f "$pub" ]]; then
    note "skip ssh key (present: $key)"
  elif (( DRY_RUN )); then
    printf '+ ssh-keygen -t ed25519 -f %q -C %q -N ""\n' "$key" "hookey@${host_id}-github" >&2
  else
    ssh-keygen -t ed25519 -f "$key" -C "hookey@${host_id}-github" -N "" -q
    chmod 700 "$HOME/.ssh"
    chmod 600 "$key"
    chmod 644 "$pub"
    note "generated $key (empty passphrase)"
  fi

  if [[ -f "$ssh_config" ]] && grep -qE '^Host[[:space:]]+github\.com([[:space:]]|$)' "$ssh_config"; then
    note "skip ssh config Host github.com (already present)"
  elif (( DRY_RUN )); then
    printf '+ append Host github.com to %q\n' "$ssh_config" >&2
  else
    if [[ -f "$ssh_config" && -s "$ssh_config" ]]; then
      printf '\n' >> "$ssh_config"
    fi
    cat >> "$ssh_config" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
EOF
    chmod 600 "$ssh_config"
    note "appended Host github.com to $ssh_config"
  fi

  if [[ ! -f "$pub" ]]; then
    note "skip allowed_signers (no pubkey)"
  else
    read -r algo blob _ < "$pub"
    if [[ -f "$signers" ]] && grep -qF "$blob" "$signers"; then
      note "skip allowed_signers (key already listed)"
    elif (( DRY_RUN )); then
      printf '+ append signer to %q\n' "$signers" >&2
    else
      printf '%s %s %s hookey@%s-github\n' "$email" "$algo" "$blob" "$host_id" >> "$signers"
      note "appended signing key to $signers"
    fi
  fi

  if (( DRY_RUN )); then
    note "dry-run: skip GitHub key upload"
    return 0
  fi
  if [[ "$HOME" != "$REAL_HOME" ]]; then
    note "HOME!=REAL_HOME; skip GitHub key upload"
    return 0
  fi
  if [[ ! -f "$pub" ]]; then
    note "skip GitHub key upload (no pubkey)"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    note "gh not on PATH; skip GitHub key upload"
    _github_ssh_print_sop "$pub" "$host_id"
    return 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    note "gh not logged in; skip GitHub key upload"
    _github_ssh_print_sop "$pub" "$host_id"
    return 0
  fi

  local list
  if ! list="$(gh ssh-key list 2>/dev/null)"; then
    note "gh ssh-key list failed (need admin:public_key,admin:ssh_signing_key)"
    _github_ssh_print_sop "$pub" "$host_id"
    return 0
  fi

  read -r algo blob _ < "$pub"
  if ! _github_ssh_ensure_uploaded "$pub" "$list" "$blob" authentication "$host_id"; then
    _github_ssh_print_sop "$pub" "$host_id"
    return 0
  fi
  if ! _github_ssh_ensure_uploaded "$pub" "$list" "$blob" signing "signing-${host_id}"; then
    _github_ssh_print_sop "$pub" "$host_id"
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_flags "$@"

  guard_canonical_root

  BACKUP_TS="$(date -u +%Y%m%dT%H%M%SZ)"

  log "install.sh start (dry_run=$DRY_RUN no_symlink=$NO_SYMLINK)"
  note "repo root: $REPO_ROOT"
  [[ -n "${TARGET_HOME:-}" ]] && note "TARGET_HOME override: HOME=$HOME (real: $REAL_HOME)"

  detect_os
  sudo_keepalive
  ensure_pkg_manager
  install_core_packages
  setup_zsh
  init_submodules
  symlink_dotfiles
  symlink_submodule_overrides
  setup_github_ssh_signing

  if (( WITH_NODE ));     then install_node;     fi
  if (( WITH_GO ));       then install_go;       fi
  if (( WITH_RUST ));     then install_rust;     fi
  if (( WITH_NVIM ));     then install_nvim_deps; fi
  if (( WITH_DOCKER ));   then install_docker;   fi
  if (( WITH_LATEX ));    then install_latex;    fi
  if (( WITH_CRG ));      then install_crg;      fi
  if (( WITH_PROJECTS )); then install_projects; fi
  if (( WITH_SECRETS ));  then seed_secrets;     fi
  if (( WITH_CLAUDE_AGENTS )); then
    install_claude_agents
    verify_claude_parity
  fi

  log "done"
}

# Run main only when invoked directly. Sourcing the file (e.g. for unit tests
# that want to extract individual functions like seed_env) skips main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
