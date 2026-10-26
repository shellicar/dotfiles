#!/bin/sh
# vscode-open-workspace starts its detached check with stdin from /dev/null,
# on the belief that run-shell's stdin is a socket tmux waits on until nothing
# holds it. This checks that belief against the real tmux: a run-shell command
# (no -b, as the focus hook runs it) has a socket as stdin, and run-shell does
# not return while a process the command left behind still holds that stdin,
# though it returns at once when the same process has /dev/null instead.
#
# run-shell is called directly rather than through a pane-focus-in hook, which
# needs an attached client to fire; it is the same job handling either way.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a

# readlink runs as its own process with the command's stdin, so it names that.
tm run-shell 'readlink /proc/self/fd/0 > /work/stdin'
stdin=$(cat /work/stdin)
case "$stdin" in
  socket:*) ok "run-shell's stdin is a socket ($stdin)" ;;
  *) fail "run-shell's stdin is not a socket: [$stdin]" ;;
esac

# A background process in a non-interactive sh gets /dev/null as stdin unless
# it is given another, so the held case passes the command's own stdin through
# descriptor 3. stdout and stderr go to /dev/null in both, so stdin is the only
# thing the left-behind sleep can hold.
#
# Timed with /proc/uptime, not date: the wall clock date reads can be stepped
# backwards mid-run, and once read 3s for a run-shell that waited the full 4s.
# Uptime only moves forward. Linux prints it with two decimals, so dropping
# the dot gives hundredths of a second.
uptime_cs() {
  read -r up _ < /proc/uptime
  echo "${up%.*}${up#*.}"
}
seconds() { # <hundredths>
  printf '%d.%02ds' $(($1 / 100)) $(($1 % 100))
}
elapsed() { # <run-shell command>: hundredths of a second until run-shell returns
  start=$(uptime_cs)
  tm run-shell "$1"
  echo $(($(uptime_cs) - start))
}

held=$(elapsed 'exec 3<&0; sleep 4 <&3 3<&- > /dev/null 2>&1 & exit 0')
[ "$held" -ge 350 ] || fail "run-shell returned after $(seconds "$held") while a process held its stdin; expected about 4s"
ok "run-shell waited $(seconds "$held") for a process holding its stdin"

free=$(elapsed 'sleep 4 < /dev/null > /dev/null 2>&1 & exit 0')
[ "$free" -le 100 ] || fail "run-shell took $(seconds "$free") when the process had /dev/null as stdin; expected at once"
ok "run-shell returned in $(seconds "$free") when the process had /dev/null as stdin"

echo 'PASS run-shell-waits-for-whatever-holds-its-stdin'
