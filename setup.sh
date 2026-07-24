#!/bin/sh
# Bootstrap dispatcher. Detects the OS and runs its setup.
# Safe on a bare machine: needs only /bin/sh and the OS base (get-os.sh uses uname).

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/resolve-os.sh"
os=$(resolve_os "$("$DIR/get-os.sh")")

target="$DIR/setup/$os/setup.sh"
if [ ! -x "$target" ]; then
  echo "No setup script for OS: $os ($target)" >&2
  exit 1
fi

exec "$target"
