# ~/.zprofile — sourced by login zsh shells only. Cheap env exports live in ~/.zshenv.
# This file is for login-only setup: heavy commands (forks, IPC), tty operations, and
# session-boundary behaviors that don't belong in every shell invocation.

# Linux util-linux mesg: deny terminal write/wall messages. Tty-guarded so non-tty login
# contexts (ssh Command=, scripts) don't error.
[[ "$OSTYPE" == linux* ]] && [ -t 0 ] && command -v mesg >/dev/null && mesg n 2>/dev/null

# macOS-only optional Homebrew toolchains (heavy paths). brew shellenv is in .zshenv.
if [[ "$OSTYPE" == darwin* ]]; then
  for d in /opt/homebrew/opt/llvm/bin /opt/homebrew/opt/openjdk/bin /opt/homebrew/opt/rustup/bin; do
    [[ -d "$d" ]] && export PATH="$d:$PATH"
  done
  [[ -d /opt/homebrew/opt/openjdk/include ]] && export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include"
fi

# Go: use `go env GOPATH` (forks the go binary, heavy → login-only). Fix: only $gopath/bin
# belongs on PATH; the bare $gopath was a GOPATH-root pollution bug.
if command -v go >/dev/null 2>&1; then
  gopath="$(go env GOPATH)"
  export PATH="$gopath/bin:$PATH"
  unset gopath
elif [[ ! "$PATH" == *"$HOME/go/bin"* ]]; then
  export PATH="${PATH:+${PATH}:}$HOME/go/bin"
fi

# macOS-only: zathura dbus setup
if [[ "$OSTYPE" == darwin* ]]; then
  DBUS_LAUNCHD_SESSION_BUS_SOCKET="$(launchctl getenv DBUS_LAUNCHD_SESSION_BUS_SOCKET)"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_LAUNCHD_SESSION_BUS_SOCKET"
fi
