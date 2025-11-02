#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]]  && . ~/.bashrc
[[ -d ~/.local./bin ]] && export PATH=$PATH:~/.local/bin

HISTSIZE=1000000000
export HISTSIZE

# Ensure screen uses user based .screen dir
if command -v screen &> /dev/null ; then
  export SCREENDIR=$HOME/.screen
  [ -d $SCREENDIR ] || mkdir -p -m 700 $SCREENDIR
fi

if command -v vim &> /dev/null ; then
  export EDITOR='vim'
  alias vi=vim
else
  export EDITOR='vi'
fi
export PATH="~/bin/:$PATH"

# For pyenv
if command -v pyenv &> /dev/null ; then
  export PYENV_ROOT="$HOME/.pyenv"
  [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init - bash)"
fi

# setup ssh-agent # TODO
[ -e ~/bin/ssh_agenter.sh ] && source ~/bin/ssh_agenter.sh

# Git status for prompt.
git_branch() {
  # Exit early if not in a git repository.
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

  local ref 
  ref=$(git symbolic-ref --quiet --short HEAD)

  if [ -z "$ref" ]; then
    # We are in a detached HEAD state.
    # Try to find a tag that points exactly to this commit.
    ref=$(git describe --tags --exact-match HEAD 2>/dev/null)
    if [ -z "$ref" ]; then
      # If no tag, use the short commit hash, wrapped in parens.
      ref="($(git rev-parse --short HEAD))"
    fi  
  fi  

  # Detecting a dirty working tree.
  local DIRT dirty=()
  if ! git diff --quiet --ignore-submodules 2>/dev/null || ! git diff --cached --quiet --ignore-submodules 2>/dev/null; then
    dirty+=('\033[31mchanges\033[33m')
  fi  
  if [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    dirty+=('\033[91mnew_files\033[33m')
  fi  
  (( ${#dirty[@]} > 0 )) && DIRT=" ${dirty[@]}" || DIRT=''

  echo -e "\n\033[33m[ $ref${DIRT} ]\033[00m"
}
# ... With tweak if running in WSL
__locale_info=$(sed -nE '/^PRETTY_NAME/s/.*"(.*)".*/\1/p' /etc/os-release)
case "$(uname -r)" in
  *Microsoft*|*microsoft* ) PS1="\033[32m\u\033[00m@\033[93m\h \033[94m(WSL) \[\033[32m\]\w\[\033[00m\]\$(git_branch)\n\$ " ;;
  *                       ) PS1="\033[32m\u\033[00m@\033[93m\h \[\033[32m\]\w\[\033[00m\]\$(git_branch)\n\$ " ;;
esac

# Handy funcs
alias urldecode='python3 -c "import sys, urllib.parse as ul; print(ul.unquote_plus(sys.argv[1]))"'
alias urlencode='python3 -c "import sys, urllib.parse as ul; print (ul.quote_plus(sys.argv[1]))"'
