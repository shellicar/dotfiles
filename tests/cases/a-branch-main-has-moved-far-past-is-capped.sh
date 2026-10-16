#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch main has moved past by more than the distance cap is capped"

# The distance is how far main has moved past the branch's fork, counted on the
# graph, so near and far differ only in that distance.
#
# The fake has no commit dates: it answers %ct with nothing, which the age check
# reads as 0, so the age half of the cap always holds here. Once the fake models
# dates, these commits need ones older than MAX_AGE_DAYS before NOW.
#
#   main   A - B - C - D
#   near           \ N        main is 1 past the fork (D)
#   far        \ F            main is 2 past the fork (C, D)
commit A
commit B A
commit C B
commit D C
commit N C
commit F B

ref_set refs/heads/main D
ref_set refs/remotes/origin/HEAD D
ref_set refs/heads/near N
ref_set refs/heads/far F

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

NOW=1000000000
MAX_DISTANCE=1
MAX_AGE_DAYS=30

branch_beyond_cap refs/heads/near && near=capped || near=evaluated
branch_beyond_cap refs/heads/far && far=capped || far=evaluated

expected="near=evaluated far=capped"
actual="near=$near far=$far"
assert_eq "$actual" "$expected"
