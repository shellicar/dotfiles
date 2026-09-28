#!/bin/sh
# WSL additions on top of the Linux setup: the WSL packages, then the
# gpg-bridge. setup.sh runs setup/linux/setup.sh before this; run alone, this
# does only the WSL additions.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# 1. APT packages only WSL needs.
sudo apt-get update
# shellcheck disable=SC2046
sudo apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' "$DIR/packages")

# 2. Reach the card held by the Windows gpg-agent. Needs step 1's packages and
#    the gpg-bridge.service unit that install.sh links, which the Linux setup
#    runs.
"$DOTFILES/home/wsl/bin/gpg-bridge-install" --apply
