#!/bin/sh
# GPG setup dispatcher. Detects the OS and runs its implementation.
#
# The two are not variants of one procedure. On macOS the card is local, so the
# work is gpg-agent, the login keychain and pinentry. Under WSL the card belongs
# to Windows and is reached over the socket bridge, so there is no local agent to
# configure and the work is the keyring and the bridge. Sharing one file would
# mean branching on the OS inside it, which the repo does not do: the path is the
# condition.
#
# Dispatch is on the RAW get-os.sh value, not resolve_os. resolve_os collapses
# wsl to linux for directory selection, and that is exactly wrong here: a native
# Linux box needs pcscd and scdaemon locally, not a bridge to Windows. Its own
# header sanctions the raw value for callers that must tell the two apart.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
os=$("$DIR/get-os.sh")

target="$DIR/setup/$os/gpg-setup.sh"
if [ ! -x "$target" ]; then
  echo "No GPG setup for OS: $os ($target)" >&2
  exit 1
fi

exec "$target" "$@"
