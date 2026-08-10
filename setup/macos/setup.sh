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

# 3. Node toolchain (fnm and pnpm are installed by the Brewfile). Pick a
#    Node version to taste:
# fnm install --lts
# fnm default <version>

# 4. GitVersion, both majors. The `gitversion` wrapper picks one per repo from
#    that repo's GitVersion.yml, so a machine carrying only one still fails
#    wherever the other is wanted.
"$DIR/../install-gitversion.sh" 5
"$DIR/../install-gitversion.sh" 6

# 5. Link the configs into $HOME.
"$DOTFILES/install.sh"
