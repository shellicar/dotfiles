#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'run bare from a pane whose server lost its socket, the command refuses the server now on that label'

LIVE_PID=$WORK/live-pid
tmux_says() {
  case "$*" in
    "-u -L my,label display-message -p #{pid}") cat "$LIVE_PID" ;;
    *) fail "unexpected: tmux $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

# The socket path holds a comma, so $TMUX is cut from the right.
TMUX=/tmp/tmux-1000/my,label,4242,0
LABEL='' LABEL_SET=0

echo 4242 > "$LIVE_PID"
resolve_target 2>/dev/null || fail "the pane's own server was refused"
assert_eq "$TS_LABEL" 'my,label'

echo 5151 > "$LIVE_PID"
err=$( (resolve_target) 2>&1) && fail "an orphaned pane was let through"
assert_contains "$err" "orphaned 'my,label' server (pid 4242)"
assert_contains "$err" "pid 5151"

# -L is a deliberate target and is not checked.
LABEL=other LABEL_SET=1
resolve_target || fail "-L was checked"
assert_eq "$TS_LABEL" other
