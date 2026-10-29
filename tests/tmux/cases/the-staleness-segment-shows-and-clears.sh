#!/bin/sh
# The status-right "SNAPSHOT STALE" segment, exactly as .tmux.conf sets it, is a
# pure tmux format (no #(), so no socket and no shell-out): it shows once the
# last save is older than the threshold, is empty while the save is current, and
# before the first save falls back to #{start_time} so a new server is not
# flagged. It is gated on the whole server being non-trivial (its panes across
# every session and window), mirroring save's own single-pane refusal: a server
# with one pane in all is never saved, so an always-old time must not warn. The
# count is whole-server, not per-session, so a trivial session of a non-trivial
# server is still warned. Because the segment needs no socket, the server keeps
# rendering it even after its socket is deleted; the last step shows that against
# a real attached client.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a
# A second pane makes the server non-trivial, so the warning is not suppressed.
tm split-window -h -t main:0 -c /work/b
settle

# status-right exactly as .tmux.conf sets it, plus a 1s redraw so a capture is
# current.
grep '^set -g status-right ' /repo/home/common/.tmux.conf > /work/status.conf
[ -s /work/status.conf ] || fail "no status-right line in .tmux.conf"
tm source-file /work/status.conf || fail "the status-right line does not load"
tm set -g status-interval 1

# A pure format: no #() shell-out, which is what lets it render with no socket.
case $(tm show -gv status-right) in *'#('*) fail "status-right shells out with #()" ;; esac
ok "the segment is a pure format (no #() shell-out)"

shown() { tm display-message -p -t "$1" "$(tm show -gv status-right)"; }

# A save well past the threshold (now - 1000 > 600): the non-trivial server is
# stale.
tm set-option -s @snapshot-last-save "$(( $(date +%s) - 1000 ))"
case $(shown main:0.0) in *'SNAPSHOT STALE'*) ;; *) fail "an old save does not show stale on a non-trivial server: $(shown main:0.0)" ;; esac
ok "an old save shows on a non-trivial server: $(shown main:0.0)"

# A separate server with a single session, window and pane is trivial as a whole,
# so the same old save does not warn it. (A trivial session of a non-trivial
# server would still warn; the gate counts the whole server, not one session.)
T2=trivial
tmux -L "$T2" -f /dev/null new-session -d -s only -x 200 -y 50
tmux -L "$T2" source-file /work/status.conf || fail "status-right did not load on the trivial server"
tmux -L "$T2" set-option -s @snapshot-last-save "$(( $(date +%s) - 1000 ))"
triv=$(tmux -L "$T2" display-message -p -t only:0.0 "$(tmux -L "$T2" show -gv status-right)")
tmux -L "$T2" kill-server 2>/dev/null
case $triv in *'SNAPSHOT STALE'*) fail "an old save warns a trivial single-pane server: $triv" ;; esac
ok "an old save does not warn a trivial single-pane server (whole-server gate)"

# A current save (now): not stale.
tm set-option -s @snapshot-last-save "$(date +%s)"
case $(shown main:0.0) in *'SNAPSHOT STALE'*) fail "a current save shows stale: $(shown main:0.0)" ;; esac
ok "a current save shows nothing stale"

# No save yet: falls back to #{start_time}, and the server has just started, so
# it is not flagged.
tm set-option -su @snapshot-last-save
case $(shown main:0.0) in *'SNAPSHOT STALE'*) fail "a just-started server with no save shows stale: $(shown main:0.0)" ;; esac
ok "an unset save falls back to start_time and is not flagged"

# Rendering after the socket is deleted. A client must stay attached, so an outer
# tmux server hosts a pane that attaches to this one; deleting the socket leaves
# the open connection intact, and the server keeps redrawing its own bar on the
# status-interval tick. The save starts below the threshold (not yet stale), so
# STALE appearing only after the socket is gone and the clock has crossed 600
# proves the bar kept rendering without the socket, not that it was stale from
# the first frame.
tm set-option -s @snapshot-last-save "$(( $(date +%s) - 580 ))"
O=outer
tmux -L "$O" -f /dev/null new-session -d -x 200 -y 50
tmux -L "$O" send-keys -t 0 "TMUX= tmux -L $L -f /dev/null attach -t main" Enter
sleep 2
case $(tmux -L "$O" capture-pane -p -t 0) in
  *'SNAPSHOT STALE'*) fail "the bar showed stale before the threshold was crossed" ;;
esac
ok "a save below the threshold is not yet flagged"
sock=$(tm display-message -p '#{socket_path}')
rm -f "$sock"
sleep 25
cap=$(tmux -L "$O" capture-pane -p -t 0)
tmux -L "$O" kill-server 2>/dev/null
case $cap in
  *'SNAPSHOT STALE'*) ok "the bar went stale after the socket was deleted and the clock crossed the threshold" ;;
  *) fail "the attached client did not go stale after socket deletion:
$cap" ;;
esac

echo 'PASS the-staleness-segment-shows-and-clears'
