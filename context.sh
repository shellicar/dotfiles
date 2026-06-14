#!/bin/sh
# Resolve dotfiles location + OS once per shell tree, exported so child shells
# inherit them and get-os.sh isn't re-forked on every shell.

export DOTFILES="${DOTFILES:-$HOME/dotfiles}"
export DOTFILES_OS="${DOTFILES_OS:-$("$DOTFILES/get-os.sh")}"
