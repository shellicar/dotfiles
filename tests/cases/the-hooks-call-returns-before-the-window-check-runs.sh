#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "the hook's call returns before the window check runs"

# The hook's run-shell waits for this command, and the check takes about half a
# second, which would land on every pane switch. The call starts a detached copy
# with setsid -f and returns. The check is held at a gate here, so a call that
# ran the check itself, or waited for the copy, would not have returned yet.
WS=$WORK/weaver.code-workspace
FAKE_GATE=$WORK/gate
FAKE_TITLES=''
FAKE_CODE_STATUS=1

run_first_call weaver "$WS"
assert_eq "$OPEN_STATUS" 0
[ ! -e "$CHECK_DONE" ] || fail "the call returned only after the check finished"
assert_eq "$(cat "$SETSID_LOG")" "-f $REPO/home/wsl/bin/vscode-open-workspace weaver $WS"

# The copy carries on: once the gate opens it checks and runs code. code fails
# here so the copy has something to say, and it says it in the log rather than
# on the caller's stderr.
wait_for "$CHECK_STARTED" || fail "the detached copy never ran the check"
: > "$FAKE_GATE"
n=0
while ! grep -q 'failed' "$OPEN_LOG" 2> /dev/null && [ "$n" -lt 50 ]; do
  sleep 0.1
  n=$((n + 1))
done
assert_eq "$(code_ran_with)" "$WS"
assert_contains "$(cat "$OPEN_LOG")" "code $WS failed"
assert_eq "$(cat "$WORK/stderr")" ''
