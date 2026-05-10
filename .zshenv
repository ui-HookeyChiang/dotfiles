# ~/.zshenv — sourced for ALL zsh invocations (login + non-login, interactive + non-interactive).
# Keep this file fast and free of side-effects. Login-only setup belongs in ~/.zprofile.

# OS detection (zsh builtin OSTYPE — no fork)
case "$OSTYPE" in
  darwin*) IS_MAC=1 ;;
  linux*)  IS_LINUX=1 ;;
esac

# Editor & version control
export EDITOR='nvim'
export DEBEMAIL="hookey.chiang@ui.com"
export DEBFULLNAME="HookeyChiang"

# History (bash-style HISTFILESIZE kept for compat; zsh uses HISTSIZE/SAVEHIST)
export HISTFILESIZE=120000
export HISTSIZE=120000
export SAVEHIST=120000

# Build / dev
export USE_CCACHE=1

# fzf preview using bat (bat available via batcat symlink on Linux; native on macOS)
export FZF_DEFAULT_OPTS='--preview "bat --style=numbers --color=always {}"'

# tmux: tell oh-my-tmux to load user override from ~/.tmux.conf.local (a symlink
# to dotfiles/.tmux.conf.local) rather than the submodule's vanilla template.
export TMUX_CONF_LOCAL="$HOME/.tmux.conf.local"

# TERM — feature-detect via terminfo presence (works on both macOS and Linux paths)
if [[ -z "$TERM" || "$TERM" == "dumb" ]]; then
  if infocmp xterm-256color >/dev/null 2>&1; then
    export TERM='xterm-256color'
  else
    export TERM='screen-256color'
  fi
fi

# PATH base — universal entries every shell needs
typeset -U path  # zsh: dedup PATH entries automatically
path=("$HOME/.local/bin" $path)

# macOS Homebrew shellenv (also handles Intel via /usr/local fallback).
# This belongs here (not .zprofile) so IDE-spawned shells on macOS get brew on PATH.
if (( IS_MAC )) && [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# Linux-only: ensure ~/.local/bin/bat -> /usr/bin/batcat (Ubuntu ships bat as batcat).
# Idempotent: skip if symlink already in place.
if (( IS_LINUX )) && command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
  if [[ ! -L "$HOME/.local/bin/bat" ]]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
fi
