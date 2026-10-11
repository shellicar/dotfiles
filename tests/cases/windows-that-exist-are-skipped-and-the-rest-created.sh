#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a window is skipped only when its session exists and has that index'

# work exists with windows 0 and 2. Window 1 is missing, and so is 2 of notes,
# a session that does not exist even though another session has a window 2.
# Window indexes are compared as the numbers tmux prints, and 10 is not 1.
FAKE_SESSIONS="\$1${FUS}work"
FAKE_WINDOWS="\$1${FUS}0
\$1${FUS}2
\$1${FUS}10"
tmux_says() { fake_listing "$@" || fail "unexpected: tmux $*"; }

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

# Given out of order, as a file would never be but a sort must cope with.
panes=$(
  snap_pane work 10 ten 0
  snap_pane work 2 two 0
  snap_pane work 1 one 0
  snap_pane work 0 zero 0
  snap_pane notes 2 todo 0
  snap_pane work 1 one 1
)
panes=$(printf '%s\n' "$panes" | sort_panes)
plan_for_server "$panes"

expected="$(snap_line create-session notes)
$(snap_line create-window notes 2 todo 1)
$(snap_line create-window work 1 one 2)
$(snap_line skip-window work 0)
$(snap_line skip-window work 2)
$(snap_line skip-window work 10)
"
assert_eq "$PLAN" "$expected"
