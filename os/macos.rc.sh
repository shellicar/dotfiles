#!/bin/sh
# macOS interactive.

# ls -> GNU coreutils (gls); plain ls is already GNU on Linux
alias ls='gls --color=auto -l'

command -v fnm >/dev/null && eval "$(fnm env --use-on-cd)"
# fnm's env eval prepends its own bin dir, ahead of PNPM_BIN from path.sh (env
# phase runs first). PNPM_BIN holds the native pnpm and the commands global
# installs add; re-prepend it so both come ahead of a corepack pnpm in that
# Node's bin dir.
path_prepend "$PNPM_BIN"
