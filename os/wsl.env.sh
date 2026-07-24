#!/bin/sh
# WSL environment. WSL is Debian/Ubuntu underneath, so it shares the linux
# environment (pnpm, ZScaler certs, ...). Add WSL-only bits below.
[ -f "$DOTFILES/os/linux.env.sh" ] && . "$DOTFILES/os/linux.env.sh"

export BROWSER="wslview"
