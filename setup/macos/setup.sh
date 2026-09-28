#!/bin/sh
# macOS bootstrap: Homebrew -> declared packages -> link configs.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# Installers are downloaded here whole and run from the file, so a failed or
# cut-short download is never run: `bash -c "$(curl …)"` runs an empty string
# as success when curl fails.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Homebrew. Its installer also pulls in the Xcode Command Line Tools
#    (git, compilers), which breaks the no-git / no-brew chicken-and-egg.
#    NONINTERACTIVE=1 makes the installer run `sudo -n`, which aborts when
#    sudo is locked. `sudo -v` unlocks it first.
if ! command -v brew >/dev/null 2>&1; then
  sudo -v
  curl -fsSL -o "$tmp/homebrew-install.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
  NONINTERACTIVE=1 /bin/bash "$tmp/homebrew-install.sh"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

# 2. Declared dependencies.
cat "$DOTFILES/setup/Brewfile" "$DIR/Brewfile" | brew bundle --file=-

#    pnpm, into the PNPM_HOME that os/macos.env.sh sets.
. "$DOTFILES/os/macos.env.sh"
"$DOTFILES/setup/install-pnpm.sh"

"$DOTFILES/setup/check-corepack.sh"
"$DOTFILES/setup/check-tmux.sh"

# 3. Node toolchain. Pick a Node version to taste:
# fnm install --lts
# fnm default <version>

# 4. GitVersion, both majors. The `gitversion` wrapper picks one per repo from
#    that repo's GitVersion.yml, so a machine carrying only one still fails
#    wherever the other is wanted.
"$DIR/../install-gitversion.sh" 5
"$DIR/../install-gitversion.sh" 6

# 5. Link the configs into $HOME.
"$DOTFILES/install.sh"
