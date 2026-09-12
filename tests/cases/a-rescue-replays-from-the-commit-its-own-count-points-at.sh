#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a rescue replays from the commit its own count points at"

# The count says how many commits above the join point are not in main. The join
# point is found by counting that many back from the tip, and everything above
# it is replayed onto a rescue branch before the original is deleted.
#
# Get it wrong and the rescue takes the wrong commits, and the delete that
# follows it takes the rest. That is the only place in these commands where work
# goes with nothing saying so, and it has happened: the count used to be
# smuggled inside the reason text and parsed back out of it, so rewording the
# reason changed how many commits were rescued.
#
#   feature/x   base - A - B - C - D      2 commits not in main
#
# Two above the join means the join is B, C and D are replayed, and A and B are
# already in main.

git_says() {
  case "$*" in
    "merge-base refs/heads/feature/x refs/remotes/origin/HEAD") echo base ;;
    # git prints a range newest first, which is why the count reads as an offset
    # from the tip rather than from the fork.
    "rev-list base..refs/heads/feature/x") printf 'D\nC\nB\nA\n' ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

ROWS=''
emit feature/xR on rescue 'rescue 2 off feature/x, then remove it' /wt/x \
  'merged, 2 commits on top not in main' - 2 review '[5 ahead, 1 week ago]'

PLAN=''
build_plan

expected='replays from B, keeping 2'
actual=$(printf '%s' "$PLAN" |
  awk -F"$TAB" '$1 == "rescue" { printf "replays from %s, keeping %s", $3, $4; exit }')
assert_eq "$actual" "$expected"
