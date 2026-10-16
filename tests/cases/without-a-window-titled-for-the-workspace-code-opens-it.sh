#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "without a window titled for the workspace, code opens it"

WS=$WORK/weaver.code-workspace

# No VS Code window at all.
FAKE_TITLES=''
run_open_workspace weaver "$WS"
assert_eq "$OPEN_STATUS" 0
assert_eq "$(code_ran_with)" "$WS"

# Titles that hold the name but do not start with "<name> - ": another server
# whose name begins with this one, the name further along, the name without the
# separator, and a name that differs only in case.
FAKE_TITLES='weaver-old - main - repo
@shellicar - weaver - repo
weaver
Weaver - main - repo'
run_open_workspace weaver "$WS"
assert_eq "$OPEN_STATUS" 0
assert_eq "$(code_ran_with)" "$WS"

# The name is matched as text, not as a pattern.
FAKE_TITLES='weaver - main - repo'
run_open_workspace 'w*' "$WS"
assert_eq "$(code_ran_with)" "$WS"
