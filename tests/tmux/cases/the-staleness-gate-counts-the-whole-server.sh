#!/bin/sh
# The staleness gate counts the whole server, not the attached session. A client
# attached to a single-pane, single-window session of a server that is non-trivial
# elsewhere must still see SNAPSHOT STALE when a save is overdue: that client's
# own session looks trivial, but the server is not, and the server is what the
# sweep saves. A per-session gate would wrongly suppress the warning from this
# exact view, which is the silent failure #71 exists to surface.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

# One non-trivial session (two panes) and one single-pane single-window session,
# on the same server.
new_session big edit /work/a
tm split-window -h -t big:0 -c /work/b
tm new-session -d -s solo -x 200 -y 50 -c /work/a
settle

grep '^set -g status-right ' /repo/home/common/.tmux.conf > /work/status.conf
[ -s /work/status.conf ] || fail "no status-right line in .tmux.conf"
tm source-file /work/status.conf || fail "the status-right line does not load"
tm set -g status-interval 1

# A save well past the threshold.
tm set-option -s @snapshot-last-save "$(( $(date +%s) - 1000 ))"

# Attach a real client to the single-pane session. An outer tmux hosts a pane
# that attaches to it, and capturing the outer pane reads the inner client's
# whole screen, status bar included.
O=outer
tmux -L "$O" -f /dev/null new-session -d -x 200 -y 50
tmux -L "$O" send-keys -t 0 "TMUX= tmux -L $L -f /dev/null attach -t solo" Enter
sleep 2
cap=$(tmux -L "$O" capture-pane -p -t 0)
tmux -L "$O" kill-server 2>/dev/null
case $cap in
  *'SNAPSHOT STALE'*) ok "a client in the single-pane session of a non-trivial server is warned" ;;
  *) fail "the single-pane session's client was not warned though the server is non-trivial:
$cap" ;;
esac

echo 'PASS the-staleness-gate-counts-the-whole-server'
