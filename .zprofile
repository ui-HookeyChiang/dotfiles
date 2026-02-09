# ~/.profile: executed by Bourne-compatible login shells.

export EDITOR='nvim'
export HISTFILESIZE=120000
export USE_CCACHE=1
export FZF_DEFAULT_OPTS='--preview "bat --style=numbers --color=always {}"'

if [ -e /usr/share/terminfo/x/xterm-256color ]; then
  export TERM='xterm-256color'
else
  # to allow home/end key in nvim
  export TERM='screen-256color'
fi

if [ -f ~/.config/tmux.default/tmux.conf.local ]; then
  cat ~/.config/tmux.default/tmux.conf.local >> ~/.config/tmux/.tmux.conf.local
  mv ~/.config/tmux/.tmux.conf.local ~/.config/tmux/tmux.conf.local
  mv ~/.config/tmux/.tmux.conf ~/.config/tmux/tmux.conf
  rm -r ~/.config/tmux.default
fi

mesg n

export PATH="$HOME/.local/bin:/opt/local/bin:/opt/local/sbin:$PATH"

# Ubuntu ships bat as batcat - create symlink if needed
if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
fi

if [ `command -v homebrew` ] || [ -d /opt/homebrew/bin ]; then
  export PATH="/opt/homebrew/bin:$PATH"
  export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
  export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
  export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include"
  export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
fi

if [ `command -v go` ]; then
  gopath=`go env GOPATH`
  export PATH=$gopath:$gopath/bin:$PATH
elif [[ ! "$PATH" == */home/${USER}/go/bin* ]]; then
  export PATH="${PATH:+${PATH}:}/home/${USER}/go/bin"
fi

# Setup deb env
export DEBEMAIL="hookey.chiang@ui.com"
export DEBFULLNAME="HookeyChiang"

# zathura dbus setup (macOS only)
if [[ "$OSTYPE" == "darwin"* ]]; then
  DBUS_LAUNCHD_SESSION_BUS_SOCKET=`launchctl getenv DBUS_LAUNCHD_SESSION_BUS_SOCKET`
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_LAUNCHD_SESSION_BUS_SOCKET"
fi