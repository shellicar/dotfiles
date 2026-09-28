#!/bin/sh
# Linux environment.

# Homebrew, installed by setup/linux/setup.sh.
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# ZScaler certs (Linux)
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# pnpm (from Homebrew, not corepack). PNPM_HOME just gives global installs a
# stable home independent of which node version is active, in the XDG data
# directory. path.sh prepends PNPM_BIN to PATH.
export PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
export PNPM_BIN="$PNPM_HOME/bin"

# rust (rustup, ~/.cargo)
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
