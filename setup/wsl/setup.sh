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
