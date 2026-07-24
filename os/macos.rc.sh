#!/bin/sh
# macOS interactive.

# ls -> GNU coreutils (gls); plain ls is already GNU on Linux
alias ls='gls --color=auto -l'

command -v fnm >/dev/null && eval "$(fnm env --use-on-cd --corepack-enabled)"
