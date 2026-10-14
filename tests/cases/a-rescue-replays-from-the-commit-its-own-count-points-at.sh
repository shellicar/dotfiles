#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a rescue replays from the branch's landed commit"

# Everything above the landed commit is replayed onto a rescue branch, and then
# the original is deleted. Get the commit wrong and the rescue takes the wrong
# commits, and the delete that follows it takes the rest. That is the only place
# in these commands where work goes with nothing saying so, and it has happened:
# the count used to be smuggled inside the reason text and parsed back out of
# it, so rewording the reason changed how many commits were rescued.
#
#   main        base - T
#   feature/x   base - A - B - C - D      B landed in main, 2 commits on top
#
# The rescue starts at B, so C and D are replayed. The row's own count is
# carried along and says so.
commit base
commit T base
commit A base
commit B A
commit C B
commit D C
lands B

ref_set refs/heads/main T
ref_set refs/remotes/origin/HEAD T
ref_set refs/heads/feature/x D

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

ROWS=''
emit feature/xR on rescue 'rescue 2 off feature/x, then remove it' /wt/x \
  'merged, 2 commits on top not in main' - 2 review '[4 ahead, 1 week ago]'

PLAN=''
build_plan

expected='replays from B, keeping 2'
actual=$(printf '%s' "$PLAN" |
  awk -F"$TAB" '$1 == "rescue" { printf "replays from %s, keeping %s", $3, $4; exit }')
assert_eq "$actual" "$expected"
