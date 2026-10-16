#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../ff-tree.sh
. "$TESTS/ff-tree.sh"

describe "ff --help prints the usage"

assert_eq "$(ff_status --help)" 0

# The whole of stdout, so nothing from find comes after the usage.
help=$(cd "$FF_ROOT" && HOME=$WORK/home "$REPO/home/common/bin/ff" --help 2>/dev/null)
assert_eq "$help" "ff: find under the current directory, skipping the directories that swamp the results

ff [--help] [--worktrees] [--] [find expression]

--worktrees  also search Claude Code worktrees, which are skipped by default
--           ends the options; everything after it is the find expression
--help       prints this usage and exits"
