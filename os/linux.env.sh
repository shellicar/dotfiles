#!/bin/sh
# Linux environment.

# Homebrew, installed by setup/linux/setup.sh.
# TODO(undecided): how a shell on a machine without Homebrew yet is kept
# working. For now the line is skipped when brew is not there, silently.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# ZScaler certs (Linux)
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# pnpm (installed natively, not via corepack). PNPM_HOME just gives global
# installs a stable home independent of which node version is active.
# path.sh prepends PNPM_BIN to PATH.
export PNPM_HOME="$HOME/.local/share/pnpm"
export PNPM_BIN="$PNPM_HOME/bin"

# rust (rustup, ~/.cargo)
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
