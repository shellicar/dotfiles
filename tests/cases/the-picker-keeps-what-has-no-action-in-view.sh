#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "the picker draws what has no valid action below its rows, and the rows give way to keep it in view"

# A worktree with no branch that is locked or dirty has no row on the list, so
# this section is the only place it is said. Printed only before the picker
# opens, it is hidden for as long as you are picking.

git_says() { fail "drawing asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# A terminal 12 rows high.
stty() { [ "$1" = size ] && { echo '12 80'; return 0; }; return 1; }

# Six branches with an update each, so six rows on the list.
#
# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors
BFACTS=''
for b in one two three four five six; do
  BFACTS="${BFACTS}feature/$b${TAB}/wt/$b${TAB}unmerged${TAB}1${TAB}-1${TAB}unmerged${TAB}1${TAB}-${TAB}ff${TAB}-${TAB}-${TAB}[1 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-$NL"
done
# Two worktrees with no branch, both locked, so two lines in the section.
#
# name, worktree, head, in main, merged PR, open PR, closed PR, block, refs,
# ignored, meta
DFACTS=''
for w in agent-a agent-b; do
  DFACTS="${DFACTS}$w${TAB}/wt/$w${TAB}abc${TAB}yes${TAB}-${TAB}-${TAB}-${TAB}locked: claude session $w (pid 4242 start 1234567)${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]$NL"
done

derive
screen=$(draw)

assert_contains "$screen" 'Looked at, no valid action'
assert_contains "$screen" 'agent-a'
assert_contains "$screen" 'locked: claude session agent-b (pid 4242 start 1234567)'

# Below the rows, above the footer.
order=$(printf '%s\n' "$screen" | awk '
  /feature\/three/ && !r { r = NR }
  /Looked at, no valid action/ && !s { s = NR }
  / selected / && !f { f = NR }
  END { print (r && s && f && r < s && s < f) ? "in order" : "out of order" }')
assert_eq "$order" 'in order'

# 12 rows: header, blank and footer take 4, one is spare, and the section takes
# 4 (a blank, its heading, two lines), which leaves 3 for the list.
assert_contains "$screen" 'showing 1-3 of 6'
