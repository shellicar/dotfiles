#!/bin/sh
# The command with no library beside it (a pull caught half way) exits non-zero
# and writes nothing.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
settle
run -L "$L" save || fail "the first save failed"
before=$(files_digest "$SNAP")

mkdir -p /work/lonely/bin
cp /repo/home/common/bin/tmux-snapshot /work/lonely/bin/
CMD=/work/lonely/bin/tmux-snapshot
tm split-window -h -t main:0 -c /work/a
settle

run -L "$L" save && fail "save without its library succeeded"
grep -q 'cannot read its library' /work/out || fail "the message does not say what is missing"
ok "exits non-zero, saying the library is missing"
[ "$(files_digest "$SNAP")" = "$before" ] || fail "the snapshot directory changed"
ok "the snapshot directory is unchanged"
tm show -gv @snapshot-error | grep -q 'cannot read its library' || fail "@snapshot-error does not say it"
ok "the server is marked: $(tm show -gv @snapshot-error)"

echo 'PASS without-its-library-save-writes-nothing'
