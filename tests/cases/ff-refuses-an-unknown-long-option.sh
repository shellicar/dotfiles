#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff refuses an unknown long option"

assert_eq "$(ff_status --worktree -name a.py)" 64

err=$(cd "$FF_ROOT" && HOME=$WORK/home "$REPO/home/common/bin/ff" --worktree -name a.py 2>&1 >/dev/null)
assert_contains "$err" "ff: unknown option --worktree"
assert_contains "$err" "ff [--worktrees] [--] [find expression]"
