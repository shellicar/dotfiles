#!/bin/sh
# restore without --apply prints the plan and leaves the server as it was.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
tm new-window -d -t main:2 -n logs -c /work/c
settle
run -L "$L" save || fail "save failed"

tm kill-window -t main:2
settle
before=$(state)

run -L "$L" restore || fail "the dry run failed"
grep -q '^DRY RUN' /work/out || fail "no DRY RUN line"
grep -q '^create window: main:2 "logs" (1 pane)' /work/out || fail "the missing window is not in the plan"
grep -q '^skip window: main:0 (exists)' /work/out || fail "the existing window is not shown as skipped"
ok "the plan names the missing window and the skipped one"

same_state "$before" "the server is unchanged"

echo 'PASS a-dry-run-changes-nothing'
