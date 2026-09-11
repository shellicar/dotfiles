#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a removal a dirty worktree blocked still decides the update's default"

# An update starts where its own removal starts, so a branch the command wants
# deleted is not quietly maintained instead.
#
# The pothole is that a dirty worktree stops the removal ROW being emitted, and
# the variable holding it is cleared on the way past. Reading that, rather than
# what the class offered, turns "do not delete this by default" into
# "fast-forward it by default" on the very branch the command decided should go.
# The branch then reads as freshly touched to every age signal, which is the
# evidence that it was abandoned.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# An empty branch: nothing of its own, so git cleanup holds its deletion behind
# --empty and this must not tick anything for it. Its worktree is dirty, so the
# removal is blocked, and it is one commit behind, so an update is available.
#
# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash
BFACTS="empty/one${TAB}/wt/one${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}1${TAB}worktree has uncommitted changes${TAB}ff${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no$NL"
DFACTS=''

derive

expected='the update is off'
state=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "empty/oneU" { print $2; exit }')
case "$state" in
  off) actual='the update is off' ;;
  '')  actual='there is no update row at all' ;;
  *)   actual="the update is $state" ;;
esac
assert_eq "$actual" "$expected"
