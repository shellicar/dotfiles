#!/bin/sh
# Linux bootstrap (Debian/Ubuntu): APT packages -> Homebrew -> declared packages
# -> link configs.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$DIR/../.." && pwd)

# Installers are downloaded here whole and run from the file, so a download cut
# short is never run as a partial script.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. APT packages, including what Homebrew's installer needs.
sudo apt-get update
# shellcheck disable=SC2046
sudo apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' "$DIR/packages")

# 2. Homebrew, into its default prefix /home/linuxbrew/.linuxbrew.
#    NONINTERACTIVE=1 makes the installer run `sudo -n`, which aborts when sudo
#    is locked, as it can be again once the apt-get above outlasts sudo's
#    timeout. `sudo -v` unlocks it first.
#    shellenv is given the shell name so it does not run ps (see
#    os/linux.env.sh).
if ! command -v brew >/dev/null 2>&1 && [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  sudo -v
  curl -fsSL -o "$tmp/homebrew-install.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
  NONINTERACTIVE=1 /bin/bash "$tmp/homebrew-install.sh"
fi
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv sh)"

# 3. Declared dependencies.
brew bundle --file="$DOTFILES/setup/Brewfile"

#    pnpm, into the PNPM_HOME that os/linux.env.sh sets.
. "$DOTFILES/os/linux.env.sh"
"$DOTFILES/setup/install-pnpm.sh"

"$DOTFILES/setup/check-corepack.sh"
"$DOTFILES/setup/check-tmux.sh"

# 4. Rust via rustup's own script, which installs to ~/.rustup and ~/.cargo.
#    --no-modify-path stops the installer from editing shell rc files (it
#    would add `. "$HOME/.cargo/env"`); the dotfiles put ~/.cargo/bin on PATH
#    in os/linux.env.sh instead. -y answers its prompts so setup runs unattended.
#    The download and the arguments are from
#    https://rust-lang.github.io/rustup/installation/other.html.
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

# 7. The directory for bash's HISTFILE, which bash will not create.
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/bash"
