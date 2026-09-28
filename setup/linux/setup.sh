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
#    shellenv does the same for the rest of this script, given the shell name
#    so it does not run ps (see os/linux.env.sh).
#    NONINTERACTIVE=1 is the installer's documented switch for running without
#    prompts. It also makes the installer call sudo with -n, which never asks
#    for a password and aborts the install with "Insufficient permissions"
#    when sudo is locked. sudo -v first asks for the password if sudo is
#    locked, which it can be again when the apt-get above outlasted sudo's
#    timeout (15 minutes by default), so the install then runs unattended.
if ! command -v brew >/dev/null 2>&1 && [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  sudo -v
  curl -fsSL -o "$tmp/homebrew-install.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
  NONINTERACTIVE=1 /bin/bash "$tmp/homebrew-install.sh"
fi
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv sh)"

# 3. Declared dependencies. Linux has no Brewfile of its own, so this is only
#    the one it shares with macOS (fnm, tmux, go).
brew bundle --file="$DOTFILES/setup/Brewfile"

#    pnpm, from its own installer, into the PNPM_HOME os/linux.env.sh gives
#    shells.
. "$DOTFILES/os/linux.env.sh"
"$DOTFILES/setup/install-pnpm.sh"

#    Then report any Node version whose corepack pnpm could answer ahead of
#    that one.
"$DOTFILES/setup/check-corepack.sh"

#    And warn when Homebrew's tmux is not the only one on PATH.
"$DOTFILES/setup/check-tmux.sh"

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
