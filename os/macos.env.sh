#!/bin/sh
# macOS environment.

eval "$(/opt/homebrew/bin/brew shellenv)"

# pnpm. path.sh prepends PNPM_BIN to PATH.
export PNPM_HOME="$HOME/Library/pnpm"
export PNPM_BIN="$PNPM_HOME"

# rust (rustup, ~/.cargo)
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac

# ZScaler certs (macOS)
export NODE_EXTRA_CA_CERTS="$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem"
export REQUESTS_CA_BUNDLE="$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem"
