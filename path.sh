#!/bin/sh
# User-private bins — prepended LAST so they take precedence over Homebrew etc.
# load.sh sources this at the very end of the env phase; its position is the rule.

# Move $1 to the front of PATH, dropping any existing copy, so the env phase
# running twice (.zshenv, then .zprofile after path_helper) leaves one entry.
path_prepend() {
  [ -d "$1" ] || return 0
  _new=; _rest=$PATH
  while [ -n "$_rest" ]; do
    case "$_rest" in
      *:*) _seg=${_rest%%:*}; _rest=${_rest#*:} ;;
      *)   _seg=$_rest; _rest= ;;
    esac
    [ "$_seg" = "$1" ] || _new=${_new:+$_new:}$_seg
  done
  PATH="$1${_new:+:$_new}"
  unset _new _rest _seg
}

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"
export PATH
