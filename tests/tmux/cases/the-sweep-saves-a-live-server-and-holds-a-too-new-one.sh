#!/bin/sh
# The sweep against a real server: a server younger than the interval is held
# (nothing worth saving yet), and once it is past the hold it is saved and its
# @snapshot-last-save is recorded. The sweep logic is sourced from the library
# and driven with a short interval, since the production interval is five minutes.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh
# shellcheck source=../../../home/common/lib/tmux-snapshot.sh
. /repo/home/common/lib/tmux-snapshot.sh

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
settle

# Just started, so younger than a 2s interval: held.
tmux_snapshot_sweep 2 0 10
[ -f "$SNAP/current.snap" ] && fail "the sweep saved a server younger than the interval"
ok "a too-new server is held"

sleep 3
tmux_snapshot_sweep 2 0 10
[ -f "$SNAP/current.snap" ] || fail "the sweep did not save a server past the hold"
last=$(tm show -sv @snapshot-last-save) || fail "@snapshot-last-save was not recorded"
case $last in '' | *[!0-9]*) fail "@snapshot-last-save is not an epoch: $last" ;; esac
ok "a server past the hold is saved and records @snapshot-last-save=$last"

echo 'PASS the-sweep-saves-a-live-server-and-holds-a-too-new-one'
