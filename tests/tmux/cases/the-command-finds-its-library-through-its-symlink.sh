#!/bin/sh
# install.sh links the command into ~/bin and the library into ~/lib, one
# symlink each. Run as ~/bin/tmux-snapshot, the command finds ~/lib.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

mkdir -p "$HOME/bin" "$HOME/lib"
ln -s /repo/home/common/bin/tmux-snapshot "$HOME/bin/tmux-snapshot"
ln -s /repo/home/common/lib/tmux-snapshot.sh "$HOME/lib/tmux-snapshot.sh"
CMD=$HOME/bin/tmux-snapshot

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
settle

run -L "$L" save || fail "save through the symlink failed"
[ -f "$SNAP/current.snap" ] || fail "nothing was saved"
ok "saved through ~/bin/tmux-snapshot"

echo 'PASS the-command-finds-its-library-through-its-symlink'
