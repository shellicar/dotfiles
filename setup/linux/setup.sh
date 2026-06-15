#!/bin/sh
# Linux bootstrap (Debian/Ubuntu): packages -> link configs.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# 1. APT packages (apt already ships, so no package-manager bootstrap needed).
sudo apt-get update
# shellcheck disable=SC2046
sudo apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' "$DIR/packages")

# 2. fnm is not in apt — install via its script:
# curl -fsSL https://fnm.vercel.app/install | bash

# 3. Link the configs into $HOME.
"$DOTFILES/install.sh"
