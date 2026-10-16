#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff -- ends its options"

found=$(ff_in "$FF_ROOT" --worktrees -- -name a.py)
assert_eq "$found" ".claude/worktrees/one/a.py
a.py"

# After --, --worktrees is find's, and find rejects it. Only the exit status is
# asserted: GNU find, BSD find and bfs word the error differently.
status=$(ff_status -- --worktrees -name a.py)
case $status in
  0|64) fail "after --, --worktrees should reach find and fail there; ff exited $status" ;;
esac
