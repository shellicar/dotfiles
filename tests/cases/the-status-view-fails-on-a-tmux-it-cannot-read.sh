#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'on a tmux that escapes the separator, the status view fails and says why instead of claiming there is nothing'

# Two labels hold snapshots and both servers answer, through a tmux that prints
# the separator as '\037'.
FAKE_TMUX_35=1
FAKE_SESSIONS="\$0${FUS}work"
FAKE_WINDOWS="\$0${FUS}0"
tmux_says() {
  [ "$*" = -V ] && { echo 'tmux 3.5a'; return 0; }
  case "$*" in "-u -L one "* | "-u -L two "*) ;; *) fail "unexpected: tmux $*" ;; esac
  fake_listing "$@" && return 0
  [ $? -eq 2 ] || return 1
  fail "unexpected: tmux $*"
}

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

SERVER_DIR=$WORK/no-sockets
for label in one two; do
  mkdir -p "$(snapshot_dir "$label")"
  snap_file "$(snapshot_dir "$label")/current.snap" "$(snap_pane work 0 code 0)"
done

( cmd_status ) > "$WORK/out" 2> "$WORK/err" && fail "the status view succeeded on a tmux it cannot read"
assert_contains "$(cat "$WORK/err")" 'tmux printed the field separator as something else (tmux 3.5a)'
assert_not_contains "$(cat "$WORK/out")" 'no snapshots'
