#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'once a snapshot is restored, planning it again creates nothing'

# The server holds exactly what the snapshot has, under new ids, as it would
# after a first --apply. Names with ':' and '.' are matched as names.
FAKE_SESSIONS="\$4$FUS
\$7${FUS}a:b.c"
FAKE_WINDOWS="\$4${FUS}0
\$4${FUS}3
\$7${FUS}1"
tmux_says() { fake_listing "$@" || fail "unexpected: tmux $*"; }

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

panes=$(
  snap_pane '' 0 one 0
  snap_pane '' 3 two 0
  snap_pane '' 3 two 1
  snap_pane a:b.c 1 three 0
)
plan_for_server "$panes"

assert_eq "$(plan_count create-session)" 0
assert_eq "$(plan_count create-window)" 0
assert_eq "$(plan_count skip-window)" 3
