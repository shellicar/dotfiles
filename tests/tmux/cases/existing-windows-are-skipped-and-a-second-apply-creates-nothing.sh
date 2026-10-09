#!/bin/sh
# Only what is missing is created; applying the same snapshot again creates
# nothing and fails on nothing.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
tm new-window -d -t main:1 -n one -c /work/b
tm new-window -d -t main:4 -n four -c /work/c
tm split-window -v -t main:4 -c /work/a
new_session other notes /work/c
settle
saved=$(state)
run -L "$L" save || fail "save failed"

# Window 1 and the whole of other go; window 0 gets an extra pane, which a
# skipped window keeps, since restore does not touch what exists.
tm kill-window -t main:1
tm kill-session -t other
tm split-window -h -t main:0 -c /work/c
settle
main0=$(state | grep '^\[main\] 0 ')

run -L "$L" restore --apply || fail "restore failed"
grep -q 'created 2 window(s), skipped 2' /work/out || fail "expected 2 created and 2 skipped"
ok "created the 2 missing windows, skipped the 2 that exist"
settle
[ "$(state | grep '^\[main\] 0 ')" = "$main0" ] || fail "the existing window was changed"
ok "the existing window was left as it was"
[ "$(state | grep -v '^\[main\] 0 ')" = "$(printf '%s\n' "$saved" | grep -v '^\[main\] 0 ')" ] ||
  fail "the restored windows differ from the saved ones"
ok "the missing windows are back as saved"

after=$(state)
sessions=$(tm list-sessions | wc -l)
run -L "$L" restore --apply || fail "the second apply failed"
grep -q 'created 0 window(s), skipped 4' /work/out || fail "the second apply created something"
same_state "$after" "the second apply changed nothing"
[ "$(tm list-sessions | wc -l)" = "$sessions" ] || fail "the second apply added a session"
ok "no session added"

echo 'PASS existing-windows-are-skipped-and-a-second-apply-creates-nothing'
