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

export PATH="/opt/homebrew/bin:/opt/local/bin:/opt/local/sbin:$PATH"

