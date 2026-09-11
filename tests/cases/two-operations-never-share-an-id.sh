#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "two operations never share an id"

# The id is what a keystroke selects, so two operations sharing one means
# toggling the row you are looking at also toggles a different one, and an
# operation runs that was never selected on screen. A branch and a detached
# worktree directory of the same name is the ordinary case: worktree directories
# are usually named after the branch in them.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta
BFACTS="foo${TAB}/wt/foo${TAB}merged${TAB}3${TAB}0${TAB}merged${TAB}0${TAB}-${TAB}-${TAB}-${TAB}-${TAB}[3 ahead, 5 days ago]$NL"
# name, worktree, head, in main, merged PR, open PR, closed PR, block, refs,
# ignored, meta
DFACTS="foo${TAB}/elsewhere/foo${TAB}abc123${TAB}no${TAB}-${TAB}-${TAB}-${TAB}-${TAB}-${TAB}-${TAB}[abc123, 1 ahead, 5 days ago]$NL"

derive

expected=2
actual=$(printf '%s' "$ROWS" | cut -f1 | sort -u | grep -c .)
assert_eq "$actual" "$expected"
