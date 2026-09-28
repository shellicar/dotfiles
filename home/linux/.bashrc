# bash: interactive shells, and non-interactive ones that read this file, such
# as commands run over ssh, or a tool that sources it to build its shell (Claude
# Code does). Those get the env and the helpers, common.sh and os/<os>.rc.sh
# (fnm among them), but not bash/interactive.bash: its prompt and DEBUG trap
# write tmux title escapes into their output. Self-contained so it works whether
# or not a login file ran first.
. "$HOME/dotfiles/context.sh"
. "$DOTFILES/load.sh" env
case $- in
  *i*) . "$DOTFILES/load.sh" interactive bash ;;
  *)   . "$DOTFILES/load.sh" interactive ;;
esac
