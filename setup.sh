#!/bin/sh
# Bootstrap dispatcher. Detects the OS and runs its setup.
# Safe on a bare machine: needs only /bin/sh and the OS base (get-os.sh uses
# uname and grep).
#
# An OS with its own setup/<os>/setup.sh runs that; otherwise the one for its
# resolve_os base runs.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/resolve-os.sh"
os=$("$DIR/get-os.sh")

target="$DIR/setup/$os/setup.sh"
if [ ! -f "$target" ]; then
  os=$(resolve_os "$os")
  target="$DIR/setup/$os/setup.sh"
fi
if [ ! -x "$target" ]; then
  echo "No setup script for OS: $os ($target)" >&2
  exit 1
fi

exec "$target"
