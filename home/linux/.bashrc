# bash: interactive shells, and non-interactive ones that read this file. Those
# skip bash/interactive.bash: its prompt and DEBUG trap write tmux title escapes
# into their output. Self-contained so it works whether or not a login file ran
# first.
. "$HOME/dotfiles/context.sh"
. "$DOTFILES/load.sh" env
case $- in
  *i*) . "$DOTFILES/load.sh" interactive bash ;;
  *)   . "$DOTFILES/load.sh" interactive ;;
esac
