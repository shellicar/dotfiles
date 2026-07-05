#!/bin/sh
# macOS environment.

eval "$(/opt/homebrew/bin/brew shellenv)"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# rust (rustup, ~/.cargo)
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac

# ZScaler certs (macOS)
export NODE_EXTRA_CA_CERTS="$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem"
export REQUESTS_CA_BUNDLE="$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem"
