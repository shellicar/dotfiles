#!/bin/sh
# Linux environment.

# ZScaler certs (Linux)
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# pnpm. The binary itself comes from corepack, see os/linux.rc.sh's
# fnm env --corepack-enabled. PNPM_HOME just gives global installs a stable
# home independent of which node version is active. path.sh prepends
# PNPM_BIN to PATH.
export PNPM_HOME="$HOME/.local/share/pnpm"
export PNPM_BIN="$PNPM_HOME/bin"
