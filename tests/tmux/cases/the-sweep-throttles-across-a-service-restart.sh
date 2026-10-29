#!/bin/sh
# The throttle state lives in the server (@snapshot-last-save), not in the sweep
# process, so stopping and restarting the scheduler cannot reset it. The sweep is
# stateless: each run is a fresh process, so two separate runs already stand in
# for a stop and restart. A run too soon after the last save does nothing; once
# the interval has passed, the next run saves again.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh
# shellcheck source=../../../home/common/lib/tmux-snapshot.sh
. /repo/home/common/lib/tmux-snapshot.sh

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
settle

sleep 3
tmux_snapshot_sweep 2 0 10
first=$(tm show -sv @snapshot-last-save) || fail "the first sweep did not save"
ok "first sweep saved at $first"

# A second sweep process immediately after (as if the service had just been
# restarted): the last save is far newer than the interval, so it is throttled.
tmux_snapshot_sweep 2 0 10
again=$(tm show -sv @snapshot-last-save)
[ "$again" = "$first" ] || fail "a sweep soon after a save saved again ($first -> $again)"
ok "a restarted sweep respects the throttle from the server's own record"

# Once the interval has passed, the next sweep saves again.
sleep 3
tmux_snapshot_sweep 2 0 10
later=$(tm show -sv @snapshot-last-save)
[ "$later" != "$first" ] || fail "the sweep did not save once the interval had passed"
ok "a later sweep saves again ($first -> $later)"

echo 'PASS the-sweep-throttles-across-a-service-restart'
