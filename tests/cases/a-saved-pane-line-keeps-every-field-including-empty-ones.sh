#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a pane line written and read back keeps every field, empty ones in place, the last one included'

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

# Three panes of window 3 in the session "":
#   0: values with spaces, backslashes, leading and trailing blanks, ':' and '.',
#      and empty fields in the middle;
#   1: every field after the command empty, so the line ends in five separators;
#   2: only the last field, @status, empty.
# The cwd and command are the same so the panes sort by index alone.
layout='abcd,270x85,0,0{135x85,0,0,1,134x85,136,0,2}'
lines=$(
  snap_line '' 3 ' my win ' "$layout" 0 '/p a/a\b' node start-v2.mjs 'T:1.2' '' busy '' 'ok '
  snap_line '' 3 ' my win ' "$layout" 1 '/p a/a\b' node '' '' '' '' '' ''
  snap_line '' 3 ' my win ' "$layout" 2 '/p a/a\b' node '' 'T' 'c' 's' 'r' ''
)
case $(printf '%s\n' "$lines" | sed -n 2p) in
  *"$FUS$FUS$FUS$FUS$FUS$FUS") ;;
  *) fail "the second line does not end in empty fields, so it tests nothing" ;;
esac

dir=$(snapshot_dir fake)
snapshot_write fake '2026-10-09 07:05' "$lines" || fail "write failed: $SAVE_ERROR"
assert_eq "$(sed -n 1,2p "$dir/current.snap")" "tmux-snapshot 2${NL}saved 2026-10-09 07:05"
assert_eq "$(sed 1,2d "$dir/current.snap")" "$lines"

read_back=$(snapshot_panes "$dir/current.snap")

# Every field of one pane: <line> then the 13 expected values.
expect_pane() {
  local line
  line=$1
  shift
  parse_pane "$line" || fail "the line did not parse: $line"
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

expect_pane "$(printf '%s\n' "$read_back" | sed -n 1p)" \
  '' 3 ' my win ' "$layout" 0 '/p a/a\b' node start-v2.mjs 'T:1.2' '' busy '' 'ok '
expect_pane "$(printf '%s\n' "$read_back" | sed -n 2p)" \
  '' 3 ' my win ' "$layout" 1 '/p a/a\b' node '' '' '' '' '' ''
expect_pane "$(printf '%s\n' "$read_back" | sed -n 3p)" \
  '' 3 ' my win ' "$layout" 2 '/p a/a\b' node '' 'T' 'c' 's' 'r' ''

# A field read past the end would show here as a stray separator.
case "$P_STATUS$P_ROLE" in *"$FUS"*) fail "a separator leaked into a field" ;; esac
