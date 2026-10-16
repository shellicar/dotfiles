#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff --help prints the usage"

help=$(cd "$FF_ROOT" && HOME=$WORK/home "$REPO/home/common/bin/ff" --help 2>/dev/null)
assert_eq "$(ff_status --help)" 0
assert_contains "$help" "ff [--worktrees] [--] [find expression]"
assert_contains "$help" "--worktrees  stops Claude Code worktrees being pruned"
assert_contains "$help" "--           ends the options"
# The usage goes out before find runs, so no path from the tree is printed.
assert_not_contains "$help" "$FF_ROOT"
