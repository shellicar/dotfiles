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

# 3. pnpm (native, not corepack) is not in apt either -- install via its own
#    script. Installs to $PNPM_HOME (os/linux.env.sh), or ~/.local/share/pnpm
#    if that isn't set yet in this shell.
if ! command -v pnpm >/dev/null 2>&1 && [ ! -x "${PNPM_HOME:-$HOME/.local/share/pnpm}/pnpm" ]; then
  curl -fsSL https://get.pnpm.io/install.sh | sh -
fi

# 4. Rust via rustup's own script, which installs to ~/.rustup and ~/.cargo.
#    --no-modify-path stops the installer from editing shell rc files (it
#    would add `. "$HOME/.cargo/env"`); the dotfiles put ~/.cargo/bin on PATH
#    in os/linux.env.sh instead. -y answers its prompts so setup runs unattended.
#    The command is Rust's own, verbatim, with arguments passed the way its docs
#    show: https://rust-lang.github.io/rustup/installation/other.html
#    Only rustup is checked, so every machine gets the same rustup-managed
#    Rust: one from apt is ignored, and rustup's, first on PATH, is the one used.
if ! command -v rustup >/dev/null 2>&1 && [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi

# 5. GitVersion, both majors. The `gitversion` wrapper picks one per repo from
#    that repo's GitVersion.yml, so a machine carrying only one still fails
#    wherever the other is wanted.
"$DIR/../install-gitversion.sh" 5
"$DIR/../install-gitversion.sh" 6

# 6. Go toolchain. Ubuntu 24.04's apt has 1.22, older than repos pinning go 1.24.x; see
#    install-go.sh for why a single version is enough.
"$DIR/../install-go.sh"

# 7. Link the configs into $HOME.
"$DOTFILES/install.sh"

# 8. The directory for bash's HISTFILE (bash/interactive.bash), which bash will
#    not create.
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/bash"
