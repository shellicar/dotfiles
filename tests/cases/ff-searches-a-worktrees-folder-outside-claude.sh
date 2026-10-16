#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff searches a worktrees folder outside .claude"

found=$(ff_in "$FF_ROOT" -name c.py)
assert_eq "$found" "docs/worktrees/c.py"
