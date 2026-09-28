#!/bin/sh
# Linux bootstrap (Debian/Ubuntu): APT packages -> Homebrew -> declared packages
# -> link configs.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# Installers are downloaded here whole and run from the file, so a download cut
# short is never run as a partial script.
# TODO(undecided): a failed download stops setup here (set -e). The other way
# is to warn and carry on without that tool.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. APT packages, including what Homebrew's installer needs.
sudo apt-get update
# shellcheck disable=SC2046
sudo apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' "$DIR/packages")

# 2. Homebrew, with its official installer, into its default prefix
#    /home/linuxbrew/.linuxbrew. os/linux.env.sh puts it on PATH in new shells;
#    shellenv does the same for the rest of this script.
if ! command -v brew >/dev/null 2>&1 && [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  curl -fsSL -o "$tmp/homebrew-install.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
  /bin/bash "$tmp/homebrew-install.sh"
fi
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# 3. Declared dependencies. Linux has no Brewfile of its own, so this is only
#    the one it shares with macOS (fnm, pnpm, tmux, go).
brew bundle --file="$DOTFILES/setup/Brewfile"

# 4. Rust via rustup's own script, which installs to ~/.rustup and ~/.cargo.
#    --no-modify-path stops the installer from editing shell rc files (it
#    would add `. "$HOME/.cargo/env"`); the dotfiles put ~/.cargo/bin on PATH
#    in os/linux.env.sh instead. -y answers its prompts so setup runs unattended.
#    The download and the arguments are Rust's own, from
#    https://rust-lang.github.io/rustup/installation/other.html, with the script
#    saved to a file instead of piped into sh.
#    Only rustup is checked, so every machine gets the same rustup-managed
#    Rust: one from apt is ignored, and rustup's, first on PATH, is the one used.
if ! command -v rustup >/dev/null 2>&1 && [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  curl --proto '=https' --tlsv1.2 -sSf -o "$tmp/rustup-init.sh" https://sh.rustup.rs
  sh "$tmp/rustup-init.sh" -y --no-modify-path
fi

# 5. GitVersion, both majors. The `gitversion` wrapper picks one per repo from
#    that repo's GitVersion.yml, so a machine carrying only one still fails
#    wherever the other is wanted.
"$DIR/../install-gitversion.sh" 5
"$DIR/../install-gitversion.sh" 6

# 6. Link the configs into $HOME.
"$DOTFILES/install.sh"
