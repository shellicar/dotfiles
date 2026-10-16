#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff keeps an -o inside the expression"

# Ungrouped, the -o would split the whole expression, and a.py would print
# nothing while the worktrees' b.py escaped the prune.
found=$(ff_in "$FF_ROOT" -name a.py -o -name b.py)
assert_eq "$found" "a.py
repo/b.py"
