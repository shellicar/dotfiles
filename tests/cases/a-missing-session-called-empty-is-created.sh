#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a session called "" in the snapshot and not on the server is created like any other'

# No server: the listings fail, so everything in the snapshot is created. The
# first session in sort order is "", and it must start a session in the plan
# rather than read as "no session yet".
FAKE_SESSIONS=''
tmux_says() { fake_listing "$@" || [ $? -eq 1 ] || fail "unexpected: tmux $*"; }

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

panes=$(
  snap_pane '' 0 shell 0
  snap_pane '' 0 shell 1
  snap_pane work 2 code 0
)
plan_for_server "$panes"

expected="$(snap_line create-session '')
$(snap_line create-session work)
$(snap_line create-window '' 0 shell 2)
$(snap_line create-window work 2 code 1)
"
assert_eq "$PLAN" "$expected"
