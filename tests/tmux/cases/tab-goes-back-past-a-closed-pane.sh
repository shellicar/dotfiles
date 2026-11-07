#!/bin/sh
# The Tab binding and its focus hook, loaded from the real .tmux.conf, on a real
# server with a real client attached (focus hooks fire only for a pane a client
# is looking at, and only with focus-events on).
#
# - The hook keeps @pane-history most recent first, each pane once, starting
#   from unset, from an empty value and from a single space: the first pane
#   added must still be matched, and moved, the next time it has focus.
# - %1 moving to the front leaves %12 in place, with 100+ panes in the history.
# - Focus pane1, pane2, pane3, pane2, then close pane2: Tab lands on pane1
#   (another session), nothing is left in view mode over a pane, and a second
#   Tab returns to pane3.
# - With no other pane left, Tab shows a message and leaves the pane as it is.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

# The binding runs ~/dotfiles/.local/bin/tmux-last-pane.
ln -s /repo "$HOME/dotfiles"

conf=/repo/home/common/.tmux.conf
{
  grep '^set -g focus-events ' "$conf"
  grep "^set-hook -g 'pane-focus-in\[1\]' " "$conf"
  grep '^bind Tab ' "$conf"
} > /work/tab.conf
[ "$(wc -l < /work/tab.conf)" -eq 3 ] || fail "expected the focus-events, hook and Tab lines in .tmux.conf, found:
$(cat /work/tab.conf)"

new_session one edit /work/a
tm source-file /work/tab.conf || fail "the Tab lines do not load"
# A message stays up until a key, so it can be read off the screen.
tm set -g display-time 0

# A client attached through an outer tmux, as a terminal would be.
O=outer
tmux -L "$O" -f /dev/null new-session -d -x 200 -y 50
tmux -L "$O" send-keys -t 0 "TMUX= tmux -L $L -f /dev/null attach -t one" Enter
sleep 2

hist() { sleep 1; tm show-options -gqv @pane-history; }
on() { tm list-clients -F '#{pane_id}'; }
tab() { tmux -L "$O" send-keys -t 0 C-b Tab; sleep 1; }
in_mode() { tm list-panes -a -F '#{pane_id} #{pane_in_mode}' | grep -v ' 0$'; }

same() { # <actual> <expected> <what>
  [ "$1" = "$2" ] || fail "$3: expected [$2], got [$1]"
  ok "$3"
}

# --- the hook, from unset ---
same "$(hist)" ' %0 ' 'attaching from an unset history records the pane, padded'
tm split-window -t one:0 -c /work/b
tm select-pane -t %0
tm select-pane -t %1
tm select-pane -t %0
same "$(hist)" ' %0 %1 ' 'the first pane added is moved, not added again'

tm set -g @pane-history ''
tm select-pane -t %1
tm select-pane -t %0
same "$(hist)" ' %0 %1 ' 'from an empty value, the same'

tm set -g @pane-history ' '
tm select-pane -t %1
tm select-pane -t %0
same "$(hist)" ' %0 %1 ' 'from a single space, the same'

# --- 100+ panes, and %1 against %12 ---
i=0
while [ "$i" -lt 120 ]; do
  tm new-window -t one: -c /work/a || fail "new-window $i"
  i=$((i + 1))
done
tm switch-client -t %1
tm switch-client -t %12
tm switch-client -t %1
h=$(hist)
ids=$(printf '%s\n' "$h" | tr ' ' '\n' | grep .) # one id per line
words=$(printf '%s\n' "$ids" | wc -l)
unique=$(printf '%s\n' "$ids" | sort -u | wc -l)
same "$words" 122 'every pane is in the history'
same "$unique" 122 'no pane is in it twice'
same "$(printf '%s\n' "$ids" | head -2 | tr '\n' ' ')" '%1 %12 ' '%1 moved to the front ahead of %12'
case $h in ' '*' ') ok 'the history is padded at both ends' ;; *) fail "not padded: [$h]" ;; esac

# --- the example in #88 ---
p1=$(tm new-session -d -s p1 -x 200 -y 50 -c /work/a -P -F '#{pane_id}')
p2=$(tm new-session -d -s p23 -x 200 -y 50 -c /work/b -P -F '#{pane_id}')
p3=$(tm split-window -t "$p2" -c /work/c -P -F '#{pane_id}')
for p in "$p1" "$p2" "$p3" "$p2"; do
  tm switch-client -t "$p"
  sleep 0.3
done
tm kill-pane -t "$p2"
sleep 1
same "$(on)" "$p3" 'closing pane2 leaves the client on pane3'
case $(hist) in " $p3 $p2 $p1 "*) ok 'pane2 is still in the history until Tab' ;; *) fail "unexpected history: [$(hist)]" ;; esac

tab
same "$(on)" "$p1" 'Tab lands on pane1'
same "$(in_mode)" '' 'no pane is in view mode after Tab'
h=$(hist)
case $h in " $p1 $p3 "*) ok 'pane1 then pane3 head the history' ;; *) fail "unexpected history: [$h]" ;; esac
case $h in *" $p2 "*) fail "the closed pane2 is still in the history: [$h]" ;; esac
ok 'Tab dropped the closed pane2 from the history'

tab
same "$(on)" "$p3" 'a second Tab returns to pane3'

# --- nowhere to go ---
tm kill-session -t one
tm kill-session -t p1
tab
same "$(on)" "$p3" 'with no other pane, Tab stays put'
same "$(in_mode)" '' 'no pane is in view mode after a Tab with nowhere to go'
same "$(hist)" " $p3 " 'the history is down to the current pane'
cap=$(tmux -L "$O" capture-pane -p -t 0)
tmux -L "$O" kill-server 2>/dev/null
case $cap in
  *'no earlier pane'*) ok 'the status line says there is no earlier pane' ;;
  *) fail "no message on the status line:
$cap" ;;
esac

echo 'PASS tab-goes-back-past-a-closed-pane'
