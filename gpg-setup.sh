#!/bin/sh
# Runs this OS's GPG setup, setup/<os>/gpg-setup.sh.
#
# Uses the raw get-os.sh value, not resolve_os, which maps wsl to linux: WSL
# reaches the card through Windows, native Linux has it locally.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
os=$("$DIR/get-os.sh")

target="$DIR/setup/$os/gpg-setup.sh"
if [ ! -x "$target" ]; then
  echo "No GPG setup for OS: $os ($target)" >&2
  exit 1
fi

exec "$target" "$@"
