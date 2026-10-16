#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "the window check's lock is free once the check ends"

# A lock left held would stop every later check for the workspace, and no
# window would open for it again. The lock is flock's, released by the kernel
# when its holder exits, so nothing here releases it by hand.
WS=$WORK/weaver.code-workspace
FAKE_TITLES=''

# After opening the workspace, and after finding the window open.
run_open_workspace weaver "$WS"
assert_eq "$(checks_run)" 1
lock_is_free "$WS" || fail "the lock was held after a check that opened the workspace"
FAKE_TITLES='weaver - main - repo'
run_open_workspace weaver "$WS"
assert_eq "$(checks_run)" 1
lock_is_free "$WS" || fail "the lock was held after a check that found the window"

# Killed with SIGKILL partway through the check, so nothing of its own runs.
# The check it started is still running, and must not hold the lock either.
FAKE_GATE=$WORK/gate
PATH=$STANDINS:$FLOCKBIN VSCODE_OPEN_WORKSPACE_DETACHED=1 \
  VSCODE_OPEN_WORKSPACE_LOG=$OPEN_LOG \
  /bin/sh "$REPO/home/wsl/bin/vscode-open-workspace" weaver "$WS" 2> /dev/null &
copy=$!
wait_for "$CHECK_STARTED" || fail "the check never started"
lock_is_free "$WS" && fail "the lock was free while the check ran"
kill -9 "$copy"
wait "$copy" 2> /dev/null
lock_is_free "$WS" || fail "the lock was held after the check was killed"
: > "$FAKE_GATE"
