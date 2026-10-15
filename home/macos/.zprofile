# zsh: login shells. Runs after /etc/zprofile's path_helper, which reshuffles
# PATH. Re-assert the order with path.sh; .zshenv already set the rest of the
# environment.
. "$DOTFILES/path.sh"
