#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a read that times out with nothing typed and no resize redraws nothing"

# The picker's read gives up several times a second so a resize is noticed.
# Redrawing on each of those would flicker the screen five times a second.
#
# readkey stands in for the terminal: three reads that time out with nothing
# typed and no resize, then a quit. Only the first frame should be drawn.

git_says() { fail "drawing asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

stty() { [ "$1" = size ] && { echo '30 80'; return 0; }; return 1; }

reads=0
readkey() {
  reads=$((reads + 1))
  if [ "$reads" -le 3 ]; then KEY=none; else KEY=quit; fi
}

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors
BFACTS="feature/one${TAB}/wt/one${TAB}unmerged${TAB}1${TAB}-1${TAB}unmerged${TAB}1${TAB}-${TAB}ff${TAB}-${TAB}-${TAB}[1 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-$NL"
DFACTS=''

picker_loop > "$WORK/screen"

assert_eq "$reads" 4
frames=$(grep -c ' selected ' "$WORK/screen")
assert_eq "$frames" 1
