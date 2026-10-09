#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a pane line written and read back keeps every field, the empty ones in place'

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

# An empty first field (the session ""), empty fields in the middle, and values
# with spaces, backslashes, leading and trailing blanks, ':' and '.'.
line=$(snap_line '' 3 ' my win ' 'abcd,270x85,0,0{135x85,0,0,1,134x85,136,0,2}' 1 \
  '/path with space/a\b' 'node' 'start-v2.mjs' 'T:1.2' '' 'busy' '' 'ok ' 31337)

dir=$(snapshot_dir fake)
snapshot_write fake '2026-10-09 07:05' "$line" || fail "write failed: $SAVE_ERROR"
assert_eq "$(sed -n 1,2p "$dir/current.snap")" "tmux-snapshot 2${NL}saved 2026-10-09 07:05"
assert_eq "$(snapshot_saved "$dir/current.snap")" '2026-10-09 07:05'

parse_pane "$(snapshot_panes "$dir/current.snap")" || fail "the line did not parse"
assert_eq "$P_SESSION" ''
assert_eq "$P_WIDX" 3
assert_eq "$P_WNAME" ' my win '
assert_eq "$P_LAYOUT" 'abcd,270x85,0,0{135x85,0,0,1,134x85,136,0,2}'
assert_eq "$P_PIDX" 1
assert_eq "$P_PATH" '/path with space/a\b'
assert_eq "$P_CMD" node
assert_eq "$P_LAUNCHER" start-v2.mjs
assert_eq "$P_TITLE" 'T:1.2'
assert_eq "$P_COLOUR" ''
assert_eq "$P_STATE" busy
assert_eq "$P_ROLE" ''
assert_eq "$P_STATUS" 'ok '
assert_eq "$P_PID" 31337
