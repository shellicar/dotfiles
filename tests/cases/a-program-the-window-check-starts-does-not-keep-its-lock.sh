#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "a program the window check starts does not keep its lock"

# code run from WSL can start the VS Code server, which keeps running after
# the check ends. Had it inherited the lock's descriptor it would hold the lock
# for good, and every later check would find it held. powershell.exe is closed
# off the same way. Each stand-in here leaves a sleep running with whatever
# descriptors it was given.
WS=$WORK/weaver.code-workspace
FAKE_TITLES=''

for program in code powershell.exe; do
  FAKE_LINGER=$program
  run_open_workspace weaver "$WS"
  assert_eq "$(checks_run)" 1
  [ -s "$LINGERING" ] || fail "$program left nothing running"
  lock_is_free "$WS" || {
    end_lingering
    fail "something $program left running holds the lock"
  }
  end_lingering
done
