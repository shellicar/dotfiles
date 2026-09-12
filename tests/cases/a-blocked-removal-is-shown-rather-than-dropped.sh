#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a removal a dirty worktree blocked is shown as unavailable, not dropped"

# The row is what explains the rest of the branch. Dropped, the update below it
# sits unticked with nothing on screen saying why, and the branch reads as
# though the command had no opinion about deleting it when it had one and was
# stopped. Both halves have to be on the line: what the branch is, and what is
# in the way.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash
BFACTS="empty/one${TAB}/wt/one${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}1${TAB}worktree has uncommitted changes${TAB}ff${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no$NL"
DFACTS=''

derive

row=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "empty/oneR" { print $2 "|" $6; exit }')
expected='skip|never diverged from main, worktree has uncommitted changes'
actual=${row:-<no removal row at all>}
assert_eq "$actual" "$expected"
