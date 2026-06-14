#!/bin/sh
# Portable environment — sourced for every shell, login or not, on every OS.

export VISUAL=vim
export EDITOR="$VISUAL"
export ENABLE_LSP_TOOL=1

# gls (coreutils ls) colours — 256-colour so directories aren't the dark ANSI blue
export LS_COLORS="di=38;5;39:ln=38;5;51:ex=38;5;40:or=38;5;196"

export NVM_DIR="$HOME/.nvm"
