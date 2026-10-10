#!/bin/sh
# A session called "" is saved, counted as running by the status view, created
# with -s '' on restore, and found again by a second restore.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session '' shell /work/a
tm split-window -h -t "$(session_id '')" -c /work/b
tm new-window -d -t "$(session_id ''):2" -n two -c /work/c
new_session work code /work/b
settle
before=$(state)
printf '%s\n' "$before" | grep -q '^\[\] 0 shell' || fail "the test server has no \"\" session"

# Kill work, so the server's only session is "".
tm kill-session -t "$(session_id work)"
run || fail "the status view failed"
grep -Eq '^t +[^ ].* running ' /work/out || fail "the status view does not count the server as running"
ok "the status view counts a server whose only session is \"\" as running"
new_session work code /work/b
settle

run -L "$L" save || fail "save failed"
tm kill-server
run restore-server "$L" --apply || fail "restore failed"
settle
same_state "$before" 'the "" session and the rest are rebuilt'

run restore-server "$L" --apply || fail "the second restore failed"
grep -q 'duplicate session' /work/out && fail "the second restore tried to create the \"\" session again"
grep -q 'created 0 window(s)' /work/out || fail "the second restore created something"
ok "the second restore creates nothing"

echo 'PASS a-session-called-empty-round-trips'
