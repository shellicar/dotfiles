#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "one window check at a time per workspace"

# Fast pane switching starts a copy per focus. A check already running covers
# them, so a copy that finds the workspace's lock held runs no check.
WS=$WORK/weaver.code-workspace
OTHER=$WORK/shellicar.code-workspace
FAKE_TITLES=''

hold_lock "$WS"
run_open_workspace weaver "$WS"
assert_eq "$OPEN_STATUS" 0
assert_eq "$(checks_run)" 0
assert_eq "$(code_ran_with)" ''

# A lock held on another workspace does not stop this one.
run_open_workspace shellicar "$OTHER"
assert_eq "$OPEN_STATUS" 0
assert_eq "$(checks_run)" 1
assert_eq "$(code_ran_with)" "$OTHER"

kill -9 "$HOLDER"
