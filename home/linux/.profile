# POSIX / login env, for sh and bash login shells.
. "$HOME/dotfiles/context.sh"
. "$DOTFILES/load.sh" env

# Login bash doesn't read .bashrc on its own; pull in the interactive layer
# (prompt, colours, aliases) so interactive login shells (e.g. WSL's default)
# match. A non-interactive login bash (bash -lc) gets the env alone.
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
  case $- in
    *i*) . "$HOME/.bashrc" ;;
  esac
fi
