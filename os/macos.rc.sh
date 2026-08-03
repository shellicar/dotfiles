#!/bin/sh
# macOS interactive.

# ls -> GNU coreutils (gls); plain ls is already GNU on Linux
alias ls='gls --color=auto -l'

command -v fnm >/dev/null && eval "$(fnm env --use-on-cd)"
# fnm's env eval prepends its own bin dir, ahead of PNPM_BIN from path.sh (env
# phase runs first) -- re-prepend so native pnpm wins over any leftover shim.
path_prepend "$PNPM_BIN"
