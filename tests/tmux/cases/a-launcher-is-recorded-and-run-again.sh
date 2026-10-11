#!/bin/sh
# A pane running an allowlisted launcher under a wrapper is saved with it, and
# restore types it into the rebuilt pane. Others are left as plain shells.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

# On the login shell's PATH, which /etc/profile resets in each new pane.
mkdir -p /usr/local/bin
# shellcheck disable=SC2016 # the script's own $PWD, expanded when it runs
printf '#!/bin/sh\necho launched > /work/launched-$(basename "$PWD")\nexec sleep 1000\n' > /usr/local/bin/start-v2.mjs
chmod +x /usr/local/bin/start-v2.mjs

new_session main code /work/a
# A wrapper shell whose child runs the launcher: it is found below the pane.
tm send-keys -t main:0.0 "sh -c '/usr/local/bin/start-v2.mjs --resume x; :'" Enter
tm split-window -h -t main:0 -c /work/b
tm send-keys -t main:0.1 "sh -c 'sleep 1000 other.mjs; :'" Enter
sleep 2

run -L "$L" save || fail "save failed"
grep -q 'launcher: start-v2.mjs' /work/out || fail "the launcher was not detected"
[ "$(grep -c 'launcher:' /work/out)" = 1 ] || fail "something other than the launcher was detected"
ok "only the allowlisted launcher is recorded"

tm kill-server
rm -f /work/launched-*
run restore-server "$L" --apply || fail "restore failed"
sleep 2
[ -f /work/launched-a ] || fail "the launcher did not run in its pane's cwd"
[ -f /work/launched-b ] && fail "the other pane ran the launcher"
ok "restore ran the launcher bare in its pane"

echo 'PASS a-launcher-is-recorded-and-run-again'
