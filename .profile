#!/bin/sh

for file in .bashrc .aliases .functions .path .dockerfunc .prompt; do
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
