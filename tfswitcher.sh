#!/bin/bash

# to change from defaults run:
#   USE_CACHE=false DEBUG=true tfswitcher.sh
# specific use case; reuse tfswitchs' store:
#   BIN_DIR=~/.terraform.versions/ tfswitcher.sh

BASE_URL=https://releases.hashicorp.com/terraform
BIN_DIR=${BIN_DIR:-~/bin}
BIN_STORE=${BIN_STORE:-~/.terraform.versions} # use real tfswitch's dir
NUM_VERS_SHOW=${NUM_VERS_SHOW:-4}
USE_CACHE=${USE_CACHE:-false}
DEBUG=${DEBUG:-false}

debug() { $DEBUG || return ; echo -e "$@" | sed 's/^/DEBUG: /g' ; }

exit_err() { echo -e "$@" ; exit 1 ; }

in_arr() {
  local x=$1 ; shift
  local arr=( $@ )
  [[ " ${arr[@]} " =~ " ${x} " ]]
}

do_or_die() { eval $@ || exit_err "failed to: '$@'" ; }

use_select_ver() {
  local VER="$1"
  if [ ! -e "${BIN_STORE}/terraform_$VER" ] ; then
    echo "downloading terraform ${VER}..."
    do_or_die wget -q $BASE_URL/$VER/terraform_${VER}_linux_amd64.zip -O $BIN_STORE/terraform_temp.zip
    do_or_die unzip -qq -o -d $BIN_STORE $BIN_STORE/terraform_temp.zip
    do_or_die mv -f $BIN_STORE/terraform $BIN_STORE/terraform_${VER}
    do_or_die rm -f $BIN_STORE/terraform_temp.zip
  fi
  do_or_die ln -fs $BIN_STORE/terraform_${VER} $BIN_DIR/terraform
  echo "set terraform ver ${VER}"
}

# function from https://unix.stackexchange.com/a/415155
#   Alexander Klimetschek
#   https://unix.stackexchange.com/users/219724/alexander-klimetschek
#   tweaked moving some 
select_option() {

    # little helpers for terminal print control and key input
    ESC=$( printf "\033")
    cursor_blink_on()  { printf "$ESC[?25h"; }
    cursor_blink_off() { printf "$ESC[?25l"; }
    cursor_to()        { printf "$ESC[$1;${2:-1}H"; }
    print_option()     { printf "   $1  "; }
    print_selected()   { printf " $ESC[7m> $1 <$ESC[27m"; }
    get_cursor_row()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
    key_input()        { read -s -n3 key 2>/dev/null >&2
                         if [[ $key = $ESC[A ]]; then echo up;    fi
                         if [[ $key = $ESC[B ]]; then echo down;  fi
                         if [[ $key = ""     ]]; then echo enter; fi; }

    # initially print empty new lines (scroll down if at bottom of screen)
    for opt; do printf "\n"; done

    # determine current screen position for overwriting the options
    local lastrow=`get_cursor_row`
    local startrow=$(($lastrow - $#))

    # ensure cursor and input echoing back on upon a ctrl+c during read -s
    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    local selected=0
    while true; do
        # print options by overwriting the last lines
        local idx=0
        for opt; do
            cursor_to $(($startrow + $idx))
            if [ $idx -eq $selected ]; then
                print_selected "$opt"
            else
                print_option "$opt"
            fi
            ((idx++))
        done

        # user key control
        case `key_input` in
            enter) break;;
            up)    ((selected--));
                   if [ $selected -lt 0 ]; then selected=$(($# - 1)); fi;;
            down)  ((selected++));
                   if [ $selected -ge $# ]; then selected=0; fi;;
        esac
    done

    # cursor position back to normal
    cursor_to $lastrow
    printf "\n"
    cursor_blink_on

    return $selected
}

debug  "BASE_URL      = $BASE_URL"
debug  "BIN_DIR       = $BIN_DIR"
debug  "BIN_STORE     = $BIN_STORE"
debug  "NUM_VERS_SHOW = $NUM_VERS_SHOW"
debug  "USE_CACHE     = $USE_CACHE"

mkdir -p $BIN_DIR   || exit_err "failed to ensure $BIN_DIR exists"
mkdir -p $BIN_STORE || exit_err "failed to ensure $BIN_STORE exists"

if $USE_CACHE ; then
  debug "using cached upstream available versions from $BASE_URL"

  [ -e ${BIN_STORE}/upstream_cache ] \
  || exit_err "cache file '${BIN_STORE}/upstream_cache' not available"

  source ${BIN_STORE}/upstream_cache

  set | grep ^VERS_UPSTREAM= -q \
  || exit_err "cache file did not set VERS_UPSTREAM var"
else
  debug "getting available versions from upstream $BASE_URL"

  VERS_UPSTREAM=(
    $(
      wget $BASE_URL -qO- 2> /dev/null \
      | grep 'href.*/terraform/[0-9]\+\.[0-9]\+\.[0-9]\+"' \
      | cut -d"'" -f2 \
      | cut -d'"' -f2 \
      | cut -d / -f3 \
      | sort -rV
    )
  )

  (( ${#VERS_UPSTREAM[@]} > 0 )) \
  && ( set | grep ^VERS_UPSTREAM > ${BIN_STORE}/upstream_cache ) \
  || echo "failed to obtain available version from $BASE_URL"
fi

VERS_LOCAL=(
  $(ls -1 ${BIN_STORE}/terraform_* 2> /dev/null \ | sed 's,^.*/terraform_,,g' | sort -rV)
)

VERS_ALL=(
  $(
    echo -e "${VERS_UPSTREAM[@]} ${VERS_LOCAL[@]}" \
    | tr ' ' '\n' \
    | grep -v '^$' \
    | sort -ruV
  )
)

debug "$(set | grep -E '^VERS_(UPSTREAM|LOCAL|ALL)=')"

# if user set a ver on the command line that's available, just run with it
if in_arr "${1:-NOVERSET}" ${VERS_ALL[@]} ; then
  use_select_ver $1
  exit
fi

# use_select_ver 1.1.9

# menu to select version - unimplemented
#  reuses 'sub' functions of select_option (no suchs thing in bash) and
#  some vars from the same.
# prepare lines at end of screen and menu title
for ((x=0;x<$((NUM_VERS_SHOW + 3));x++)) ; do echo $x; done
tput cuu $((NUM_VERS_SHOW + 3))
top_row=$(IFS=';' read -sdR -p $'\E[6n' ROW COL;echo ${ROW#*[})
ver_index=0

while true ; do
  # go to top of identified lines, clear, print selection prompt
  cur_row=$(IFS=';' read -sdR -p $'\E[6n' ROW COL;echo ${ROW#*[})
  move_up=$(( $cur_row - $top_row + 1))
  (( move_up > 0 )) && tput cuu $move_up
  echo 'Select version:'
  tput dl $((NUM_VERS_SHOW + 3))
  
  # check vers - fix for sanity and prep forward/backward type options
  (( $ver_index < 0 )) && ver_index=0
  (( $ver_index > ${#VERS_ALL[@]} )) && ver_index=${#VERS_ALL[@]}
  (( $ver_index > 0 )) \
  && newer='newer' \
  || newer=''
  (( $ver_index > $(( ${#VERS_ALL[@]} - 4)) )) \
  && older='' \
  || older='older'

  select_option $newer ${VERS_ALL[@]:${ver_index}:${NUM_VERS_SHOW}} $older
  selected_option=$?

  # check to see if a real selection made
  if (( $ver_index == 0 )) ; then
    # selected a real option?
    if (( $selected_option < $((NUM_VERS_SHOW + 0)) )) ; then
      use_select_ver ${VERS_ALL[$((selected_option + $ver_index))]}
      break
    fi
  else
    # moving up/newer?
    if (( $selected_option == 0 )) ; then
      ver_index=$((ver_index - NUM_VERS_SHOW))
      continue
    fi
    # selected a real option?
    if (( $selected_option < $((NUM_VERS_SHOW + 1)) )); then
      use_select_ver ${VERS_ALL[$((selected_option + $ver_index - 1))]}
      break
    fi
  fi
  # all thats left is older
  ver_index=$((ver_index + NUM_VERS_SHOW))
done
