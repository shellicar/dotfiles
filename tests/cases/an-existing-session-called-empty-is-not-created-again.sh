#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a session called "" that exists is seen, and only its missing window is created'

# The server has the "" session with window 0. The snapshot has "" with windows
# 0 and 1, and a session called work. Reading "" as no session at all is what
# made a restore try to create it again and fail with "duplicate session: ".
FAKE_SESSIONS="\$0$FUS"
FAKE_WINDOWS="\$0${FUS}0"
tmux_says() { fake_listing "$@" || fail "unexpected: tmux $*"; }

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

panes=$(
  snap_pane '' 0 shell 0
  snap_pane '' 1 logs 0
  snap_pane work 0 code 0
)
plan_for_server "$panes"

expected="$(snap_line create-session work)
$(snap_line create-window '' 1 logs 1)
$(snap_line create-window work 0 code 1)
$(snap_line skip-window '' 0)
"
assert_eq "$PLAN" "$expected"
