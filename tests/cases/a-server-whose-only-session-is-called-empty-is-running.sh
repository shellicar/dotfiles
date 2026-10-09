#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'the status view counts a server as running when its only session is called ""'

# Asked for session names alone, this server prints one empty line, which a
# check that counts non-empty lines reads as no server.
FAKE_SESSIONS="\$0$FUS"
FAKE_WINDOWS="\$0${FUS}0"
tmux_says() {
  case "$1 $2" in
    "-L up") shift 2; FAKE_SESSIONS="\$0$FUS" fake_listing "$@" ;;
    "-L down") shift 2; FAKE_SESSIONS='' fake_listing "$@" ;;
    *) fail "unexpected: tmux $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

server_running up || fail "a server with a \"\" session read as not running"
server_running down && fail "a server that does not answer read as running"

# The status view itself: one label with a snapshot and its server up.
dir=$(snapshot_dir up)
mkdir -p "$dir"
printf 'tmux-snapshot 2\n%s\n%s\n' "$(snap_pane '' 0 a 0)" "$(snap_pane '' 1 b 0)" > "$dir/current.snap"
SERVER_DIR=$WORK/no-sockets
row=$(status_rows)
assert_eq "$row" "$(snap_line up "$(when '2026-10-09 12:00')" 1 2 2 running '1 window')"
