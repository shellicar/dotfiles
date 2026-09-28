#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "someone else's branch is offered its update unticked, and says whose it is"

# The analysis has already turned its rebase into a merge. derive leaves it
# unticked and names the other authors.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors
BFACTS="review/theirs${TAB}/wt/theirs${TAB}unmerged${TAB}2${TAB}2${TAB}work of its own${TAB}3${TAB}-${TAB}merge${TAB}-${TAB}-${TAB}[2 ahead, 1 day ago]${TAB}0${TAB}no${TAB}2 of 2 by them@example.com$NL"
BFACTS="${BFACTS}feature/mine${TAB}/wt/mine${TAB}unmerged${TAB}1${TAB}1${TAB}work of its own${TAB}3${TAB}-${TAB}rebase${TAB}B${TAB}-${TAB}[1 ahead, 1 day ago]${TAB}0${TAB}no${TAB}-$NL"
DFACTS=''

derive

row() { printf '%s' "$ROWS" | awk -F"$TAB" -v id="$1" '$1 == id { print $2 "|" $3 "|" $6; exit }'; }
assert_eq "$(row review/theirsU)" "off|merge|3 behind, not yours: 2 of 2 by them@example.com"
assert_eq "$(row feature/mineU)" "on|rebase|3 behind"
