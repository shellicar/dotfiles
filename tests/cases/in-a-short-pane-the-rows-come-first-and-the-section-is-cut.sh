#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "in a short pane the picker draws every row first, cuts the section to what is left, and never outgrows the pane"

# The rows are what you act on. A frame taller than the pane makes the terminal
# scroll, which takes the header and the cursor row off the top and leaves a
# screen with nothing on it to do.

git_says() { fail "drawing asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

HEIGHT=16
stty() { [ "$1" = size ] && { echo "$HEIGHT 80"; return 0; }; return 1; }

# Six rows on the list.
#
# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors
BFACTS=''
for b in one two three four five six; do
  BFACTS="${BFACTS}feature/$b${TAB}/wt/$b${TAB}unmerged${TAB}1${TAB}-1${TAB}unmerged${TAB}1${TAB}-${TAB}ff${TAB}-${TAB}-${TAB}[1 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-$NL"
done
# Eight locked worktrees with no branch, so eight entries in the section.
#
# name, worktree, head, in main, merged PR, open PR, closed PR, block, refs,
# ignored, meta
DFACTS=''
for n in 1 2 3 4 5 6 7 8; do
  DFACTS="${DFACTS}agent-$n${TAB}/wt/agent-$n${TAB}abc${TAB}yes${TAB}-${TAB}-${TAB}-${TAB}locked: claude session agent-$n (pid 4242 start 1234567)${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]$NL"
done

derive
screen=$(draw)

# 16 lines: the header and footer take 4 and one is spare, which leaves 11.
# The six rows take 6. The section gets 5: a blank, its heading, two entries
# and the count of the other six.
for b in one two three four five six; do
  assert_contains "$screen" "fast-forward feature/$b"
done
assert_contains "$screen" 'showing 1-6 of 6'
assert_contains "$screen" 'Looked at, no valid action'
assert_contains "$screen" 'agent-2 '
assert_not_contains "$screen" 'agent-3 '
assert_contains "$screen" '+6 more, shown after you quit'

lines=$(printf '%s' "$screen" | awk 'END { print NR }')
[ "$lines" -le "$HEIGHT" ] || fail "the frame is $lines lines in a pane of $HEIGHT"
