#!/bin/sh
# WSL bootstrap: the Linux setup, then the WSL packages, then the gpg-bridge.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# 1. Everything a Linux machine gets, ending with the configs linked into $HOME.
"$DIR/../linux/setup.sh"

# 2. APT packages only WSL needs.
sudo apt-get update
# shellcheck disable=SC2046
sudo apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' "$DIR/packages")

# 3. Reach the card held by the Windows gpg-agent. Needs step 2's packages and
#    the gpg-bridge.service unit that step 1 linked.
"$DOTFILES/home/wsl/bin/gpg-bridge-install" --apply
