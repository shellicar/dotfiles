#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "--depth bounds how far down the search for a landed commit goes"

# The search is tip first and stops after WALK_DEPTH commits. A branch whose
# landed commit sits deeper than that is reported as not checked, not as
# unmerged: nothing is known about the commits below. A branch with no more
# commits than WALK_DEPTH, none of them landed, is plainly unmerged.
#
#   main   A - M
#   deep    \ c1 - c2 - c3 - c4 - c5      c2's work landed in main
#   short   \ s1 - s2                     nothing landed
commit A
commit M A
commit c1 A
commit c2 c1
commit c3 c2
commit c4 c3
commit c5 c4
commit s1 A
commit s2 s1
lands c2

ref_set refs/heads/main M
ref_set refs/remotes/origin/HEAD M
ref_set refs/heads/deep c5
ref_set refs/heads/short s2

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

WALK_DEPTH=2
shallow=$(commits_not_in_main refs/heads/deep)
WALK_DEPTH=5
deep=$(commits_not_in_main refs/heads/deep)
short=$(commits_not_in_main refs/heads/short)

expected="shallow=-3 deep=3 short=-1"
actual="shallow=$shallow deep=$deep short=$short"
assert_eq "$actual" "$expected"
