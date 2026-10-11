#!/bin/sh
# A window with more than six panes, and one with a pane one row high. Each
# split halving the room, or a split landing on a one-row pane, stopped a
# restore before (#19, #36).
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main many /work/a
i=1
while [ "$i" -lt 8 ]; do
  tm split-window -t main:0 -c /work/b
  tm select-layout -t main:0 tiled
  i=$((i + 1))
done
tm new-window -d -t main:1 -n thin -c /work/a
tm split-window -v -t main:1 -c /work/b
tm split-window -v -l 1 -t main:1.1 -c /work/c
tm split-window -h -t main:1.0 -c /work/c
settle
before=$(state)
[ "$(tm display -p -t main:0 '#{window_panes}')" = 8 ] || fail "the test window does not have 8 panes"
tm list-panes -t main:1 -F '#{pane_height}' | grep -qx 1 || fail "the test window has no one-row pane"

run -L "$L" save || fail "save failed"
tm kill-server
run restore-server "$L" --apply || fail "restore failed"
settle
same_state "$before" "8 panes and a one-row pane restore exactly"

echo 'PASS crowded-windows-restore'
