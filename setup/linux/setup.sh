#!/bin/sh
# Linux bootstrap (Debian/Ubuntu): packages -> link configs.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# 1. APT packages (apt already ships, so no package-manager bootstrap needed).
sudo apt-get update
# shellcheck disable=SC2046
sudo apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' "$DIR/packages")

# 2. fnm is not in apt — install via its script. --skip-shell stops the
#    installer from editing shell rc files; the dotfiles wire fnm up in
#    os/linux.rc.sh instead. Installs to ~/.fnm.
if ! command -v fnm >/dev/null 2>&1 && [ ! -x "$HOME/.fnm/fnm" ]; then
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

# 3. Link the configs into $HOME.
"$DOTFILES/install.sh"
