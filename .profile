#!/bin/sh

for file in .bashrc .aliases .functions .path .dockerfunc; do
  if [ -f "$HOME/$file" ]; then
    # shellcheck source=/dev/null
	  . "$HOME/$file"
  fi
done
unset file
