# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

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

export PATH="/opt/local/bin:/opt/local/sbin:$PATH"

if [ `command -v homebrew` ] || [ -d /opt/homebrew/bin ]; then
  export PATH="/opt/homebrew/bin:$PATH"
  export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
fi

if [ `command -v go` ]; then
  gopath=`go env GOPATH`
  export PATH=$gopath:$gopath/bin:$PATH
elif [[ ! "$PATH" == */home/${USER}/go/bin* ]]; then
  export PATH="${PATH:+${PATH}:}/home/${USER}/go/bin"
fi

# Setup deb env
DEBEMAIL="hookey.chiang@ui.com"
DEBFULLNAME="HookeyChiang"
export DEBEMAIL DEBFULLNAME

# zathura dbus setup
os=`uname -s`
if [ "$os" = "Darwin" ]; then
  DBUS_LAUNCHD_SESSION_BUS_SOCKET=`launchctl getenv DBUS_LAUNCHD_SESSION_BUS_SOCKET`
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_LAUNCHD_SESSION_BUS_SOCKET"
fi
