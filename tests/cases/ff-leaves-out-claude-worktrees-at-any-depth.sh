#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff leaves out Claude worktrees at any depth"

found=$(ff_in "$FF_ROOT" -name '*.py')
assert_eq "$found" "a.py
docs/worktrees/c.py
repo/b.py"
