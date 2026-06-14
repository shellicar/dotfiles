#!/bin/sh

for file in .bashrc .aliases .functions .path .dockerfunc .prompt .certificates; do
  if [ -f "$HOME/$file" ]; then
    # shellcheck source=/dev/null
	  . "$HOME/$file"
  fi
done
unset file

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Custom
if [ -n "$WSL_DISTRO_NAME" ]; then
    export BROWSER="wslview"
fi

export VISUAL=vim
export EDITOR="$VISUAL"
export ENABLE_LSP_TOOL=1

# gls (coreutils ls) colours — 256-colour codes so directories aren't the dark ANSI blue
export LS_COLORS="di=38;5;39:ln=38;5;51:ex=38;5;40:or=38;5;196"
