#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "a failure in vscode-open-workspace still exits 0"

# The tmux focus hook ends with this command, and tmux puts the pane in view
# mode on every focus when a run-shell exits non-zero. A failure is written to
# stderr, which the hook sends to its log.
WS=$WORK/weaver.code-workspace

# The window check fails: the workspace is opened anyway.
FAKE_CHECK_STATUS=1
run_open_workspace weaver "$WS"
assert_eq "$OPEN_STATUS" 0
assert_eq "$(code_ran_with)" "$WS"
assert_contains "$(cat "$WORK/stderr")" "could not list VS Code windows"

# code fails.
FAKE_CHECK_STATUS=0
FAKE_CODE_STATUS=1
run_open_workspace weaver "$WS"
assert_eq "$OPEN_STATUS" 0
assert_contains "$(cat "$WORK/stderr")" "code $WS failed"

# Called with the wrong number of arguments.
FAKE_CODE_STATUS=0
run_open_workspace weaver
assert_eq "$OPEN_STATUS" 0
assert_eq "$(code_ran_with)" ''
assert_contains "$(cat "$WORK/stderr")" "usage:"
