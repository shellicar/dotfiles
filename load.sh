#!/bin/sh
# Router: sources the right layers for a given phase and shell.
#
#   load.sh env                  -> environment (always, login or not)
#   load.sh interactive <shell>  -> interactive config for <shell>
#
# Two dimensions decide what loads: phase (env | interactive) and os
# (from get-os.sh), plus the shell for the interactive layer. The filename
# is the condition — no runtime __is_zsh / `if linux` branching in the files.

: "${DOTFILES:=$HOME/dotfiles}"
phase="$1"
shell="$2"
os="${DOTFILES_OS:-$("$DOTFILES/get-os.sh")}"

case "$phase" in
  env)
    . "$DOTFILES/env.sh"
    [ -f "$DOTFILES/os/$os.env.sh" ] && . "$DOTFILES/os/$os.env.sh"
    . "$DOTFILES/path.sh"
    ;;
  interactive)
    . "$DOTFILES/common.sh"
    [ -f "$DOTFILES/os/$os.rc.sh" ] && . "$DOTFILES/os/$os.rc.sh"
    [ -n "$shell" ] && [ -f "$DOTFILES/$shell/interactive.$shell" ] && . "$DOTFILES/$shell/interactive.$shell"
    ;;
  *)
    echo "load.sh: unknown phase '$phase' (expected env|interactive)" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac
