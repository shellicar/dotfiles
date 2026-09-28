#!/bin/sh
# Linux environment.

# Homebrew, installed by setup/linux/setup.sh.
# The shell is named so shellenv does not run ps to guess it, for the reason on
# fnm's line in linux.rc.sh. This phase does not know which shell it is in;
# bash and sh get the same output, and only zsh would get more (its completion
# path).
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

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
