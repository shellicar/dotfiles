#!/bin/sh
# A directory holding the JSON an earlier version wrote: not offered for
# restore, and left byte for byte as it was by a save and a restore.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

mkdir -p "$SNAP"
printf '{"generated":"2026-01-01T00:00:00Z","panes":[{"session":"old"}]}\n' > "$SNAP/current.json"
printf '{"generated":"2025-12-31T00:00:00Z","panes":[]}\n' > "$SNAP/previous.json"
printf '{"half' > "$SNAP/.writing.77.json"
json() { for f in current.json previous.json .writing.77.json; do cksum "$SNAP/$f"; done; }
before=$(json)

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
settle

run -L "$L" restore && fail "a restore found a snapshot in the JSON"
grep -q "no snapshot for 't'" /work/out || fail "the refusal does not say there is no snapshot"
ok "restore finds no snapshot"
run || fail "the status view failed"
grep -Eq '^t +- +- +- +- +running +no snapshot' /work/out || fail "the status view offers something for t"
ok "the status view shows t as running with no snapshot"

run -L "$L" save || fail "save failed"
tm kill-server
run restore-server "$L" --apply || fail "restore failed"
[ "$(json)" = "$before" ] || fail "the JSON files changed"
ok "the JSON files are unchanged"
files=$(files_digest "$SNAP" | awk '{ print $3 }' | LC_ALL=C sort | tr '\n' ' ')
[ "$files" = '.writing.77.json current.json current.snap previous.json ' ] || fail "unexpected files: $files"
ok "only current.snap was added"

echo 'PASS the-old-json-snapshots-are-left-alone'
