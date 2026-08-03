#!/bin/sh
# Linux interactive.

remove_bom() {
    find . -type f -not -path '*/.git/*' -print0 | \
    xargs -0 grep -rl $'^\xEF\xBB\xBF' | \
    xargs -d '\n' sed -i '1s/^\xEF\xBB\xBF//'
}

# fnm (Node version manager). On Linux it installs to ~/.fnm and isn't on PATH
# by default, so prepend it before evaluating its environment. On macOS this is
# handled in macos.rc.sh (fnm comes from Homebrew, already on PATH).
[ -d "$HOME/.fnm" ] && PATH="$HOME/.fnm:$PATH"
command -v fnm >/dev/null && eval "$(fnm env --use-on-cd)"
# fnm's env eval prepends its own bin dir, ahead of PNPM_BIN from path.sh (env
# phase runs first) -- re-prepend so native pnpm wins over any leftover shim.
path_prepend "$PNPM_BIN"
