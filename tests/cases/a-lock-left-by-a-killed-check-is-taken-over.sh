#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "a lock left by a killed check is taken over"

# A check killed before it released the lock leaves the directory and its pid
# behind. Left alone, no window would ever open for this workspace again.
WS=$WORK/weaver.code-workspace
FAKE_TITLES=''

mkdir "$WS.lock"
dead_pid > "$WS.lock/pid"
run_open_workspace weaver "$WS"
assert_eq "$OPEN_STATUS" 0
assert_eq "$(checks_run)" 1
assert_eq "$(code_ran_with)" "$WS"
[ ! -e "$WS.lock" ] || fail "the lock taken over was not released"
