#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "an update is marked as belonging to the removal above it, when there is one"

# Two rows for one branch read as two unrelated targets otherwise, and the
# second one is unticked because of the first. The mark only goes on an update
# whose removal actually reached the screen: on a branch with no removal at all
# it would point at a line that is not there.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# empty/one has a removal on offer; idle/two is unmerged, so it has none.
#
# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash
BFACTS="empty/one${TAB}/wt/one${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}1${TAB}-${TAB}ff${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no$NL"
BFACTS="${BFACTS}idle/two${TAB}/wt/two${TAB}unmerged${TAB}3${TAB}-1${TAB}unmerged${TAB}2${TAB}-${TAB}rebase${TAB}-${TAB}-${TAB}[3 ahead, 2 days ago]${TAB}0${TAB}no$NL"
DFACTS=''

derive

mark_on() { printf '%s' "$ROWS" | awk -F"$TAB" -v k="$1" '$1 == k { print $9; exit }'; }

expected='empty/one=related idle/two=-'
actual="empty/one=$(mark_on empty/oneU) idle/two=$(mark_on idle/twoU)"
assert_eq "$actual" "$expected"
