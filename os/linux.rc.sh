#!/bin/sh
# Linux interactive.

# ls -> GNU ls with the LS_COLORS scheme from env.sh; same as gls on macOS
alias ls='ls --color=auto -l'

remove_bom() {
    find . -type f -not -path '*/.git/*' -print0 | \
    xargs -0 grep -rl "^$(printf '\357\273\277')" | \
    xargs -d '\n' sed -i '1s/^\xEF\xBB\xBF//'
}

# fnm (Node version manager). On Linux it installs to ~/.fnm and isn't on PATH
# by default, so prepend it before evaluating its environment. On macOS this is
# handled in macos.rc.sh (fnm comes from Homebrew, already on PATH).
# --shell is passed rather than inferred: fnm infers it by running ps, and Linux
# ps reads every process's cmdline, so one process wedged in the kernel hangs it
# forever and every new shell with it. load.sh sets $shell for this phase.
[ -d "$HOME/.fnm" ] && PATH="$HOME/.fnm:$PATH"
command -v fnm >/dev/null && eval "$(fnm env --use-on-cd --shell "${shell:-bash}")"
# fnm's env eval prepends its own bin dir, ahead of PNPM_BIN from path.sh (env
# phase runs first) -- re-prepend so native pnpm wins over any leftover shim.
path_prepend "$PNPM_BIN"
