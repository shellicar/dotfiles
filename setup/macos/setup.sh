#!/bin/sh
# macOS bootstrap: Homebrew -> declared packages -> link configs.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# 1. Homebrew. Its installer also pulls in the Xcode Command Line Tools
#    (git, compilers), which breaks the no-git / no-brew chicken-and-egg.
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

# 2. Declared dependencies.
brew bundle --file="$DIR/Brewfile"

# 3. Node toolchain (fnm is installed by the Brewfile). Pick a version to taste:
# fnm install --lts
# fnm default <version>
# corepack enable

# 4. Link the configs into $HOME.
"$DOTFILES/install.sh"
