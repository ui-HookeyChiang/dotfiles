set +h

if [ ! -z $(echo $PNAME | grep -o ^i686) ] || [ ! -z $(echo $PNAME | grep -o ^arm_marvell) ]; then
    . /etc/profile
fi

. ~/.git-completion.sh
. ~/.git-prompt.sh

export HISTCONTROL=ignoredups
export HISTSIZE=10000
export HISTFILESIZE=120000
export USE_CCACHE=1

PROMPT_COMMAND=__prompt_command # Func to gen PS1 after CMDs

__prompt_command() {
    local EXIT=$?             # This needs to be first
    PS1=""

    local RCol='\[\e[0m\]'

    local Red='\[\e[0;31m\]'
    local Gre='\[\e[0;32m\]'
    local BYel='\[\e[1;33m\]'
    local BBlu='\[\e[1;34m\]'
    local Pur='\[\e[0;35m\]'

    PS1="\u@$PNAME [${Red}$(__git_ps1 " %s")${RCol} ${Gre}$PWD${RCol} ] <$EXIT> \n$ "
}

alias ll='ls -lh --color=auto --time-style="+%Y%m%d%H%M.%S"'
alias ls='ls --color=auto'
alias grep='grep --color=auto'

FQDN_DISABLED=$(sed -n '/!fqdn/p' /etc/sudoers | wc -l)
GIT_PS1_SHOWUPSTREAM="auto"

if [ $FQDN_DISABLED -eq 0 ]; then
    echo
    echo "----------------------------------------"
    echo " visudo to add !fqdn to Default options"
    echo " Otherwise, you cannot build properly"
    echo "----------------------------------------"
    echo
fi


# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

#so as not to be disturbed by Ctrl-S ctrl-Q in terminals:
stty -ixon

extract () {
     if [ -f $1 ] ; then
         case $1 in
             *.tar.bz2)   tar xjf $1        ;;
             *.tar.gz)    tar xzf $1     ;;
             *.bz2)       bunzip2 $1       ;;
             *.rar)       rar x $1     ;;
             *.gz)        gunzip $1     ;;
             *.tar)       tar xf $1        ;;
             *.tbz2)      tar xjf $1      ;;
             *.tgz)       tar xzf $1       ;;
             *.zip)       unzip $1     ;;
             *.Z)         uncompress $1  ;;
             *.7z)        7z x $1    ;;
             *)           echo "'$1' cannot be extracted via extract()" ;;
         esac
     else
         echo "'$1' is not a valid file"
     fi
}

#netinfo - shows network information for your system
netinfo ()
{
echo "--------------- Network Information ---------------"
/sbin/ifconfig | awk /'inet addr/ {print $2}'
/sbin/ifconfig | awk /'Bcast/ {print $3}'
/sbin/ifconfig | awk /'inet addr/ {print $4}'
/sbin/ifconfig | awk /'HWaddr/ {print $4,$5}'
myip=`lynx -dump -hiddenlinks=ignore -nolist http://checkip.dyndns.org:8245/ | sed '/^$/d; s/^[]*//g; s/[]*$//g' `
echo "${myip}"
echo "---------------------------------------------------"
}

#dirsize - finds directory sizes and lists them for the current directory
dirsize ()
{
du -shx * .[a-zA-Z0-9_]* 2> /dev/null | \
egrep '^ *[0-9.]*[MG]' | sort -n > /tmp/list
egrep '^ *[0-9.]*M' /tmp/list
egrep '^ *[0-9.]*G' /tmp/list
rm -rf /tmp/list
}

#copy and go to dir
cpg (){
  if [ -d "$2" ];then
    cp $1 $2 && cd $2
  else
    cp $1 $2
  fi
}

#move and go to dir
mvg (){
  if [ -d "$2" ];then
    mv $1 $2 && cd $2
  else
    mv $1 $2
  fi
}
