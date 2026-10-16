#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff hands a --worktrees after the expression to find"

# Once the expression has started, ff takes no more options, so find rejects it
# rather than the results quietly changing. Only the exit status is asserted:
# GNU find, BSD find and bfs word the error differently.
status=$(ff_status -name a.py --worktrees)
case $status in
  0|64) fail "a --worktrees after the expression should make find fail; ff exited $status" ;;
esac
