#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a pane record written and read back keeps every field: empty ones, the last one, and newlines inside'

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

# Four panes of window 3 in the session "", given out of order:
#   0: values with spaces, backslashes, leading and trailing blanks, ':' and '.',
#      and empty fields in the middle;
#   1: every field after the command empty, so the record ends in five US;
#   2: only the last field, @status, empty;
#   3: newlines in the cwd, in @title and in @status, @status ending in one.
layout='abcd,270x85,0,0{135x85,0,0,1,134x85,136,0,2}'
records=$(
  snap_record '' 3 ' my win ' "$layout" 3 "/p a/nl${NL}dir" node '' "t${NL}1" '' '' '' "s${NL}t${NL}"
  snap_record '' 3 ' my win ' "$layout" 0 '/p a/a\b' node start-v2.mjs 'T:1.2' '' busy '' 'ok '
  snap_record '' 3 ' my win ' "$layout" 1 '/p a/a\b' node '' '' '' '' '' ''
  snap_record '' 3 ' my win ' "$layout" 2 '/p a/a\b' node '' 'T' 'c' 's' 'r' ''
)

dir=$(snapshot_dir fake)
snapshot_write fake '2026-10-09 07:05' "$records" || fail "write failed: $SAVE_ERROR"
assert_eq "$(sed -n 1,2p "$dir/current.snap")" "tmux-snapshot 2${NL}saved 2026-10-09 07:05"
assert_eq "$(sed 1,2d "$dir/current.snap")" "$records"
snapshot_accepts "$dir/current.snap" || fail "the file it wrote was refused"

read_back=$(snapshot_panes "$dir/current.snap")
assert_eq "$(count_records "$read_back")" 4

# Every field of the next pane read back, in sorted order.
expect_pane() { # the 13 expected values
  local rec
  rec=${read_back%%"$RS"*}
  read_back=${read_back#*"$RS"}
  read_back=${read_back#"$NL"}
  parse_pane "$rec" || fail "the record did not parse: $rec"
  assert_eq "$P_SESSION" "$1"
  assert_eq "$P_WIDX" "$2"
  assert_eq "$P_WNAME" "$3"
  assert_eq "$P_LAYOUT" "$4"
  assert_eq "$P_PIDX" "$5"
  assert_eq "$P_PATH" "$6"
  assert_eq "$P_CMD" "$7"
  assert_eq "$P_LAUNCHER" "$8"
  assert_eq "$P_TITLE" "$9"
  shift 9
  assert_eq "$P_COLOUR" "$1"
  assert_eq "$P_STATE" "$2"
  assert_eq "$P_ROLE" "$3"
  assert_eq "$P_STATUS" "$4"
}

expect_pane '' 3 ' my win ' "$layout" 0 '/p a/a\b' node start-v2.mjs 'T:1.2' '' busy '' 'ok '
expect_pane '' 3 ' my win ' "$layout" 1 '/p a/a\b' node '' '' '' '' '' ''
expect_pane '' 3 ' my win ' "$layout" 2 '/p a/a\b' node '' 'T' 'c' 's' 'r' ''
expect_pane '' 3 ' my win ' "$layout" 3 "/p a/nl${NL}dir" node '' "t${NL}1" '' '' '' "s${NL}t${NL}"

# The window is one window of four panes, not split at the newlines.
assert_eq "$(snapshot_windows "$(snapshot_panes "$dir/current.snap")")" "$(snap_line '' 3 ' my win ' 4)"
