#!/bin/sh
# The status-right "SNAPSHOT STALE" segment, exactly as .tmux.conf sets it, is a
# pure tmux format (no #(), so no socket and no shell-out): it shows once the
# last save is older than the threshold, is empty while the save is current, and
# before the first save falls back to #{start_time} so a new server is not
# flagged. Because it needs no socket, the server keeps rendering it even after
# its socket is deleted; the last step shows that against a real attached client.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a
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

shown() { tm display-message -p -t main:0 "$(tm show -gv status-right)"; }

# A save well past the threshold (now - 1000 > 600): stale.
tm set-option -s @snapshot-last-save "$(( $(date +%s) - 1000 ))"
case $(shown) in *'SNAPSHOT STALE'*) ;; *) fail "an old save does not show stale: $(shown)" ;; esac
ok "an old save shows: $(shown)"

# A current save (now): not stale.
tm set-option -s @snapshot-last-save "$(date +%s)"
case $(shown) in *'SNAPSHOT STALE'*) fail "a current save shows stale: $(shown)" ;; esac
ok "a current save shows nothing stale"

# No save yet: falls back to #{start_time}, and the server has just started, so
# it is not flagged.
tm set-option -su @snapshot-last-save
case $(shown) in *'SNAPSHOT STALE'*) fail "a just-started server with no save shows stale: $(shown)" ;; esac
ok "an unset save falls back to start_time and is not flagged"

# Rendering after the socket is deleted. A client must stay attached, so an outer
# tmux server hosts a pane that attaches to this one; deleting the socket leaves
# the open connection intact, and the server keeps redrawing its own bar.
tm set-option -s @snapshot-last-save "$(( $(date +%s) - 1000 ))"
O=outer
tmux -L "$O" -f /dev/null new-session -d -x 200 -y 50
tmux -L "$O" send-keys -t 0 "TMUX= tmux -L $L -f /dev/null attach -t main" Enter
sleep 2
sock=$(tm display-message -p '#{socket_path}')
rm -f "$sock"
sleep 2
cap=$(tmux -L "$O" capture-pane -p -t 0)
tmux -L "$O" kill-server 2>/dev/null
case $cap in
  *'SNAPSHOT STALE'*) ok "the bar still shows stale after the socket was deleted" ;;
  *) fail "the attached client did not show stale after socket deletion:
$cap" ;;
esac

echo 'PASS the-staleness-segment-shows-and-clears'
