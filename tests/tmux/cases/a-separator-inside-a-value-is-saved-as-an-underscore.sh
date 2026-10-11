#!/bin/sh
# A pane whose @status, and one whose cwd, hold US and RS (two of each): the
# save succeeds with exactly one record per pane, each US and RS saved as '_',
# and restore rebuilds the server. The cwd saved as '_' names a directory that
# does not exist, so that pane opens in HOME.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

USC=$(printf '\037')
RSC=$(printf '\036')
odd="/work/x${USC}y${RSC}z${USC}w${RSC}v"
mkdir -p "$odd" || fail "cannot make a directory with US and RS in its name"

new_session main edit /work/a
tm split-window -h -t main:0 -c "$odd"
tm set-option -p -t main:0.0 @status "a${RSC}b${USC}c${RSC}d${USC}e"
tm new-window -d -t main:1 -n other -c /work/b
settle
[ "$(tm -u display -p -t main:0.1 '#{pane_current_path}')" = "$odd" ] ||
  fail "the test pane is not in the directory with US and RS"
tm set-option -s @snapshot-error 'an earlier failure'

run -L "$L" save || fail "save failed"
tm show -sv @snapshot-error >/dev/null 2>&1 && fail "the save left @snapshot-error set"
ok "the save succeeded and cleared the mark"
records=$(sed 1,2d "$SNAP/current.snap" | tr -cd "$RSC" | wc -c | tr -d ' ')
[ "$records" = 3 ] || fail "expected 3 pane records, found $records"
ok "exactly 3 pane records"
grep -q "${USC}/work/x_y_z_w_v${USC}" "$SNAP/current.snap" || fail "the cwd was not saved as /work/x_y_z_w_v"
grep -q "${USC}a_b_c_d_e${RSC}\$" "$SNAP/current.snap" || fail "@status was not saved as a_b_c_d_e"
ok "each US and RS in a value was saved as _"

sessions_before=$(tm list-sessions -F '#{session_name}')
tm kill-server
run restore-server "$L" --apply || fail "restore failed"
settle
[ "$(tm list-sessions -F '#{session_name}')" = "$sessions_before" ] ||
  fail "the sessions differ after restore: $(tm list-sessions -F '#{session_name}')"
[ "$(tm display -p -t main:0 '#{window_panes}')" = 2 ] || fail "window 0 does not have 2 panes"
[ "$(tm display -p -t main:1 '#{window_name}')" = other ] || fail "window 1 is missing"
status=$(tm -u display -p -t main:0.0 '#{@status}')
[ "$status" = 'a_b_c_d_e' ] || fail "@status came back as: $status"
ok "restore rebuilt the server, @status as a_b_c_d_e"
tm list-windows -a -F '#{window_index}' | grep -qx 999999 && fail "a parked window was left behind"
ok "no parked window left"

echo 'PASS a-separator-inside-a-value-is-saved-as-an-underscore'
