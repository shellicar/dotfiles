#!/bin/sh
# A .snap whose version line this does not know is refused by name, and left
# as it was.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

mkdir -p "$SNAP"
printf 'tmux-snapshot 9\nwhatever a later version writes\n' > "$SNAP/current.snap"
before=$(cksum "$SNAP/current.snap")

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
settle
state_before=$(state)

run -L "$L" restore --apply && fail "a restore read an unknown version"
grep -q "refusing $SNAP/current.snap: its version line is 'tmux-snapshot 9'" /work/out ||
  fail "the refusal does not name the file and what it found"
ok "refused by name, with the version it found"
same_state "$state_before" "nothing was restored from it"
[ "$(cksum "$SNAP/current.snap")" = "$before" ] || fail "the file changed"
ok "the file is unchanged"

echo 'PASS a-snapshot-of-an-unknown-version-is-refused'
