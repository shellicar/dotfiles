#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff --worktrees searches Claude worktrees too"

found=$(ff_in "$FF_ROOT" --worktrees -name '*.py')
assert_eq "$found" ".claude/worktrees/one/.claude/worktrees/three/d.py
.claude/worktrees/one/a.py
a.py
docs/worktrees/c.py
repo/.claude/worktrees/two/b.py
repo/b.py"
