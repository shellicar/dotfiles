# bash: interactive shells, and commands run over ssh, which read this file
# without being interactive; those get the env and stop. Self-contained so it
# works whether or not a login file ran first.
. "$HOME/dotfiles/context.sh"
. "$DOTFILES/load.sh" env
case $- in *i*) ;; *) return;; esac
. "$DOTFILES/load.sh" interactive bash
