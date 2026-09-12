#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a branch with nothing on offer is listed without asking for it"

# git cleanup holds these behind -a because there they sit in the middle of its
# one list, among the branches it is offering to act on. Here they are a section
# of their own below the plan, so there is nothing to gain by withholding them,
# and withholding them meant the command knew about a branch and said nothing,
# with no way to find out it had.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# Unmerged, so no removal. Level with the trunk, so no update. Clean, so no
# block. Nothing whatever is on offer for it.
#
# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash
BFACTS="idle/one${TAB}-${TAB}unmerged${TAB}3${TAB}-1${TAB}unmerged${TAB}0${TAB}-${TAB}-${TAB}-${TAB}-${TAB}[3 ahead, 6 weeks ago]${TAB}0${TAB}no$NL"
DFACTS=''

derive

expected='idle/one  unmerged'
actual=$(printf '%s' "$NOTED" | awk -F"$TAB" '{ print $1 "  " $4; exit }')
assert_eq "$actual" "${expected:-<nothing was said about it>}"
