#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "a VS Code window already titled for the workspace is left alone"

# Running code on a workspace that is open makes its window flash, and this
# runs on every pane focus. The window is one of several, and not the first.
FAKE_TITLES='weaver - main - claude-cli
@shellicar - main - dotfiles
Welcome - Visual Studio Code'
run_open_workspace @shellicar "$WORK/shellicar.code-workspace"

assert_eq "$OPEN_STATUS" 0
assert_eq "$(code_ran_with)" ''

FAKE_TITLES='weaver - main - claude-cli'
run_open_workspace weaver "$WORK/weaver.code-workspace"
assert_eq "$OPEN_STATUS" 0
assert_eq "$(code_ran_with)" ''
