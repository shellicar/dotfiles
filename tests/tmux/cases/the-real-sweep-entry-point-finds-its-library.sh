#!/bin/sh
# The real .local/bin/tmux-snapshot-sweep, run by its repo path as the scheduler
# units run it, finds its library by repo path (that tree is not symlinked) and
# sweeps without error. Its interval is the production five minutes, so a
# just-started server is still in the first-save hold and nothing is saved.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
settle

sh /repo/.local/bin/tmux-snapshot-sweep || fail "the sweep entry-point exited non-zero"
[ -f "$SNAP/current.snap" ] && fail "the sweep saved a server inside the five-minute hold"
ok "the entry-point found its library and held a too-new server"

echo 'PASS the-real-sweep-entry-point-finds-its-library'
