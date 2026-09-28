#!/bin/sh
# Installs pnpm with pnpm's own installer (https://pnpm.io/installation), at the
# major in setup/versions, into $PNPM_HOME. The caller sets PNPM_HOME, the same
# value its OS's env file gives shells.
#
# It installs when $PNPM_HOME/bin/pnpm is missing or its --version has a major
# other than PNPM_MAJOR, and does nothing otherwise, so a new PNPM_MAJOR reaches
# every machine on its next setup. That path is the only thing checked:
# corepack's pnpm inside an fnm Node answers `command -v pnpm` too.
#
# The installer always ends with `pnpm setup`, which appends a PATH block to the
# shell's rc file. With the dotfiles linked, pnpm 11.27 writes it through the
# ~/.bashrc symlink into the repo's own home/common/.bashrc; an earlier pnpm
# replaced the symlink with a plain copy instead. With SHELL=/bin/sh it writes
# to $ENV, here a throwaway file. pnpm reads ZSH_VERSION, BASH_VERSION,
# FISH_VERSION and NU_VERSION ahead of SHELL, so those are removed for it.
#
# TODO(undecided): where PNPM_HOME comes from. For now each
# setup/<os>/setup.sh sources its os/<os>.env.sh before running this, which
# brings the rest of that file into setup too.

set -eu

DOTFILES=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=versions
. "$DOTFILES/setup/versions"

: "${PNPM_HOME:?must be set, from os/<os>.env.sh}"

if [ -x "$PNPM_HOME/bin/pnpm" ]; then
  installed=$("$PNPM_HOME/bin/pnpm" --version)
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
env -u ZSH_VERSION -u BASH_VERSION -u FISH_VERSION -u NU_VERSION \
  SHELL=/bin/sh ENV="$tmp/rc" PNPM_VERSION="$PNPM_MAJOR" \
  sh "$tmp/install.sh"
