#!/bin/sh
# macOS environment.

eval "$(/opt/homebrew/bin/brew shellenv)"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# ZScaler certs (macOS)
export NODE_EXTRA_CA_CERTS="$(brew --prefix)/etc/ca-certificates/cert.pem"
export REQUESTS_CA_BUNDLE="$(brew --prefix)/etc/ca-certificates/cert.pem"
