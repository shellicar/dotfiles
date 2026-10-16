#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff leaves out Claude worktrees several levels down"

# The * in the pattern has to match across a /, as well as within one name.
for f in \
  x/y/e.py \
  x/y/.claude/worktrees/four/e.py \
  x/y/w/.claude/worktrees/five/e.py; do
  mkdir -p "$FF_ROOT/$(dirname "$f")"
  : > "$FF_ROOT/$f"
done

found=$(ff_in "$FF_ROOT" -name e.py)
assert_eq "$found" "x/y/e.py"
