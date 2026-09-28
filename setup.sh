#!/bin/sh
# Bootstrap dispatcher. Detects the OS and runs its setup.
# Safe on a bare machine: needs only /bin/sh and the OS base (get-os.sh uses
# uname and grep).
#
# Layered the way install.sh links home/: setup/<base>/setup.sh for the
# resolve_os base runs first, then, for an OS whose base is another OS (wsl on
# linux), its own setup/<os>/setup.sh when there is one. Each script is one
# layer, so running setup/<os>/setup.sh directly runs only that layer.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/resolve-os.sh"
os=$("$DIR/get-os.sh")
base=$(resolve_os "$os")

target="$DIR/setup/$base/setup.sh"
if [ ! -x "$target" ]; then
  echo "No setup script for OS: $base ($target)" >&2
  exit 1
fi
"$target"

overlay="$DIR/setup/$os/setup.sh"
if [ "$os" != "$base" ] && [ -f "$overlay" ]; then
  "$overlay"
fi
