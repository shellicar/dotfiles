# zsh: login shells. Runs after /etc/zprofile's path_helper, which reshuffles
# PATH and pushes Homebrew ahead of the user bins. Re-assert the env phase so
# path.sh regains precedence. Mirrors what .profile does for bash login shells.
. "$DOTFILES/load.sh" env
