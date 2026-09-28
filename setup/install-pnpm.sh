#!/bin/sh
# Installs pnpm with its own installer, at the major in setup/versions, into
# $PNPM_HOME.
#
# Only $PNPM_HOME/bin/pnpm is checked: corepack's pnpm also answers
# `command -v pnpm`.
#
# The installer ends with `pnpm setup`, which appends a PATH block to the
# shell's rc file, through a linked rc into the repo. So it runs with
# SHELL=/bin/sh and ENV at a throwaway file, and with ZSH_VERSION,
# BASH_VERSION, FISH_VERSION and NU_VERSION unset, because pnpm reads those
# before SHELL.

set -eu

DOTFILES=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=versions
. "$DOTFILES/setup/versions"

: "${PNPM_HOME:?must be set, from os/<os>.env.sh}"

if [ -x "$PNPM_HOME/bin/pnpm" ]; then
  # From /: inside a project, a package.json packageManager field would pick
  # the pnpm that runs.
  installed=$(cd / && "$PNPM_HOME/bin/pnpm" --version)
  if [ "${installed%%.*}" = "$PNPM_MAJOR" ]; then
    echo "pnpm $installed already installed at $PNPM_HOME/bin/pnpm"
    exit 0
  fi
  echo "pnpm $installed at $PNPM_HOME/bin/pnpm is not major $PNPM_MAJOR; installing it"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Downloaded whole first, so a failed or cut-short download is never run.
curl -fsSL -o "$tmp/install.sh" https://get.pnpm.io/install.sh

: >"$tmp/rc"
# From / for the same reason, so `pnpm setup` is the pnpm being installed.
cd /
env -u ZSH_VERSION -u BASH_VERSION -u FISH_VERSION -u NU_VERSION \
  SHELL=/bin/sh ENV="$tmp/rc" PNPM_VERSION="$PNPM_MAJOR" \
  sh "$tmp/install.sh"
