#!/bin/sh
# Session and window names holding ':' and '.', which a target built from the
# name would misread as window and pane separators.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session 'a:b.c' 'w:1.2' /work/a
tm split-window -h -t "$(session_id 'a:b.c')" -c /work/b
tm new-window -d -t "$(session_id 'a:b.c'):3" -n 'x.y:z' -c /work/c
new_session 'a' plain /work/c
new_session '1.0' digits /work/b
settle
before=$(state)
printf '%s\n' "$before" | grep -q '^\[a:b\.c\] 0 w:1\.2' || fail "tmux did not keep the name a:b.c"
ok "tmux keeps ':' and '.' in session and window names"

run -L "$L" save || fail "save failed"
tm kill-server
run restore-server "$L" --apply || fail "restore failed"
settle
same_state "$before" "the names round-trip"

echo 'PASS names-with-colons-and-dots-round-trip'
