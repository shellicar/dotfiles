#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff started inside .claude/worktrees searches them"

# The starting directory is never pruned. The worktrees of a Claude started
# inside one of the worktrees are below it, so they still are.
found=$(ff_in "$FF_ROOT/.claude/worktrees" -name '*.py')
assert_eq "$found" "one/a.py"
