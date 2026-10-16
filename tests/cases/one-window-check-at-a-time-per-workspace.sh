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
# them, so a copy that finds the lock held by a live process runs no check.
WS=$WORK/weaver.code-workspace
FAKE_TITLES=''

mkdir "$WS.lock"
echo "$$" > "$WS.lock/pid"
run_open_workspace weaver "$WS"
assert_eq "$OPEN_STATUS" 0
assert_eq "$(checks_run)" 0
assert_eq "$(code_ran_with)" ''
assert_eq "$(cat "$WS.lock/pid")" "$$"

# A lock with no pid yet is being taken right now, and is held too.
rm "$WS.lock/pid"
run_open_workspace weaver "$WS"
assert_eq "$(checks_run)" 0
[ -d "$WS.lock" ] || fail "a lock being taken was removed"
rmdir "$WS.lock"

# A lock on another workspace does not stop this one.
mkdir "$WORK/other.code-workspace.lock"
echo "$$" > "$WORK/other.code-workspace.lock/pid"
run_open_workspace weaver "$WS"
assert_eq "$(checks_run)" 1

# A check that ran releases the lock, whether it opened a window or not.
[ ! -e "$WS.lock" ] || fail "the lock was left behind after opening"
FAKE_TITLES='weaver - main - repo'
run_open_workspace weaver "$WS"
assert_eq "$(checks_run)" 1
[ ! -e "$WS.lock" ] || fail "the lock was left behind after finding the window"
