#!/bin/sh
# save, kill the server, restore --apply: the same sessions, window indexes and
# names, pane counts, cwds, layouts and labels.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
tm split-window -v -t main:0.1 -c /work/c
tm new-window -d -t main:3 -n logs -c /work/b
tm split-window -v -t main:3 -c /work/a
tm set-option -w -t main:3 @title 'Build logs'
tm set-option -w -t main:3 @colour colour33
tm set-option -w -t main:3 @state busy
tm set-option -p -t main:3.1 @role watcher
tm set-option -p -t main:3.1 @status 'tail -f'
new_session other notes /work/c
tm new-window -d -t other:5 -n spare -c /work/a
settle
before=$(state)

run -L "$L" save || fail "save failed"
[ -f "$SNAP/current.snap" ] || fail "no current.snap"
[ "$(sed -n 1p "$SNAP/current.snap")" = 'tmux-snapshot 2' ] || fail "the first line is not the version line"
sed -n 2p "$SNAP/current.snap" | grep -Eqx 'saved [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' ||
  fail "the second line is not the save time: $(sed -n 2p "$SNAP/current.snap")"
[ "$(grep -c '^saved ' "$SNAP/current.snap")" = 1 ] || fail "the save time is written more than once"
ok "saved with the version line, then the save time once: $(sed -n 2p "$SNAP/current.snap")"
# Pane main:3.0 has its window's @title set and an empty @role and @status, so
# its line ends in empty fields, and the restore below reads it with this
# container's own sh.
US=$(printf '\037')
grep -q "${US}Build logs${US}colour33${US}busy${US}${US}\$" "$SNAP/current.snap" ||
  fail "no pane line ends in an empty @role and @status"
ok "a pane line ends in an empty @role and @status"

tm kill-server
run restore-server "$L" --apply || fail "restore failed"
settle
same_state "$before" "the rebuilt server matches the saved one"

# The parked window new-session made is gone.
tm list-windows -a -F '#{window_index}' | grep -qx 999999 && fail "a parked window was left behind"
ok "no parked window left"

echo 'PASS a-saved-server-is-rebuilt-after-it-is-killed'
