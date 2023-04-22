# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

if [ -e /usr/share/terminfo/x/xterm-256color ]; then
  export TERM='xterm-256color'
else
  export TERM='screen-256color'
fi

mesg n

export PATH="/opt/local/bin:/opt/local/sbin:$PATH"

if [ `command -v homebrew` ]; then
  export PATH="/opt/homebrew/bin:$PATH"
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
