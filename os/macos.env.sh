#!/bin/sh
# macOS environment.

eval "$(/opt/homebrew/bin/brew shellenv)"

# pnpm. path.sh prepends PNPM_BIN to PATH.
export PNPM_HOME="$HOME/Library/pnpm"
export PNPM_BIN="$PNPM_HOME/bin"

# rust (rustup, ~/.cargo)
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac

# Homebrew's bundle carries the keychain's trusted certs, Zscaler's included.
# certs.sh points Node and Python requests at it.
CA_BUNDLE_OS="$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem"
