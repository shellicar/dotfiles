#!/bin/sh
# WSL layer on top of the Linux setup.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# 1. APT packages only WSL needs.
sudo apt-get update
# shellcheck disable=SC2046
sudo apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' "$DIR/packages")

# 2. Reach the card held by the Windows gpg-agent. Needs gpg-bridge.service
#    already linked into $HOME by install.sh.
"$DOTFILES/home/wsl/bin/gpg-bridge-install" --apply

# 3. Autosave every tmux server's layout on a timer, replacing the old in-tmux
#    watcher. The units are linked into ~/.config/systemd/user by install.sh
#    (run by the linux layer above). Enabling the timer is all that is needed:
#    it runs the oneshot service, which runs .local/bin/tmux-snapshot-sweep.
systemctl --user daemon-reload
systemctl --user enable --now tmux-snapshot-sweep.timer
