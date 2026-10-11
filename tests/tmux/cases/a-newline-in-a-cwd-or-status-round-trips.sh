#!/bin/sh
# A pane whose cwd holds a newline, and one whose @status does, are saved as one
# record each: restore rebuilds them exactly and creates no session from the
# text after the newline.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

NLC='
'
mkdir -p "/work/nl${NLC}dir"

new_session main edit /work/a
tm split-window -h -t main:0 -c "/work/nl${NLC}dir"
tm set-option -p -t main:0.0 @status "two${NLC}lines"
tm new-window -d -t main:1 -n other -c /work/b
settle
[ "$(tm -u display -p -t main:0.1 '#{pane_current_path}')" = "/work/nl${NLC}dir" ] ||
  fail "the test pane is not in the directory with a newline"
sessions_before=$(tm list-sessions -F '#{session_name}')

run -L "$L" save || fail "save failed"
tm kill-server
run restore-server "$L" --apply || fail "restore failed"
settle

[ "$(tm list-sessions -F '#{session_name}')" = "$sessions_before" ] ||
  fail "the sessions differ after restore: $(tm list-sessions -F '#{session_name}')"
ok "no session was made from the text after a newline"
[ "$(tm display -p -t main:0 '#{window_panes}')" = 2 ] || fail "window 0 does not have 2 panes"
cwd=$(tm -u display -p -t main:0.1 '#{pane_current_path}')
[ "$cwd" = "/work/nl${NLC}dir" ] || fail "the cwd came back as: $cwd"
ok "the cwd with a newline came back exactly"
status=$(tm -u display -p -t main:0.0 '#{@status}')
[ "$status" = "two${NLC}lines" ] || fail "@status came back as: $status"
ok "@status with a newline came back exactly"
tm list-windows -a -F '#{window_index}' | grep -qx 999999 && fail "a parked window was left behind"
ok "no parked window left"

echo 'PASS a-newline-in-a-cwd-or-status-round-trips'
