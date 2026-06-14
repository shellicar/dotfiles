#!/bin/sh
# macOS interactive.

# ls -> GNU coreutils (gls); plain ls is already GNU on Linux
alias ls='gls --color=auto -l'

# nvm (Homebrew)
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # nvm bash_completion
