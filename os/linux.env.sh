#!/bin/sh
# Linux environment.

# Homebrew. The shell is named so shellenv does not run ps to guess it, for the
# reason on fnm's line in linux.rc.sh.
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

# ZScaler certs (Linux)
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# pnpm, the native one, not corepack's. PNPM_HOME holds pnpm, in PNPM_BIN, and
# its global installs, whichever Node version is active.
export PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
export PNPM_BIN="$PNPM_HOME/bin"

# rust (rustup, ~/.cargo)
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
