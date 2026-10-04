#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a resize while the picker is open redraws it at the new size, without a key"

# Drawn for a tall pane and left there after the pane shrinks, the frame is
# taller than the pane, and the terminal shows its bottom: no header, no cursor
# row, nothing to act on.
#
# The resize here is a real WINCH sent to this shell, caught by the trap the
# picker sets. What stands in for the terminal is readkey: the first call is a
# read that times out with nothing typed, as the picker's terminal settings
# make a read do, with the pane shrunk and the signal sent while it waits. The
# second quits. Whether a real read on a real terminal times out is not covered.

git_says() { fail "drawing asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

HEIGHT=30
stty() { [ "$1" = size ] && { echo "$HEIGHT 80"; return 0; }; return 1; }

reads=0
readkey() {
  reads=$((reads + 1))
  case "$reads" in
    1) HEIGHT=9; kill -s WINCH $$; KEY=none ;;
    *) KEY=quit ;;
  esac
}

# Six rows on the list.
#
# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors
BFACTS=''
for b in one two three four five six; do
  BFACTS="${BFACTS}feature/$b${TAB}/wt/$b${TAB}unmerged${TAB}1${TAB}-1${TAB}unmerged${TAB}1${TAB}-${TAB}ff${TAB}-${TAB}-${TAB}[1 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-$NL"
done
DFACTS=''

# Not in $(): that is a subshell, and the signal goes to this one.
picker_loop > "$WORK/screen"

# A frame for the 30-line pane, then one for the 9-line pane, which has room
# for four of the six rows.
frames=$(grep -c ' selected ' "$WORK/screen")
assert_eq "$frames" 2
last=$(grep ' selected ' "$WORK/screen" | tail -1)
assert_contains "$last" 'showing 1-4 of 6'
