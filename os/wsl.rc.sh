#!/bin/sh
# WSL interactive — WSL is Debian/Ubuntu underneath, so it shares the linux
# interactive config (fnm, remove_bom, ...). Add WSL-only bits below.
[ -f "$DOTFILES/os/linux.rc.sh" ] && . "$DOTFILES/os/linux.rc.sh"
