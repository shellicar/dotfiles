#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch is capped only when main is past it by more than the cap and it is long idle"

# The distance is how far main has moved past the branch's fork, counted on the
# graph; the age is from the tip's commit time. near and far differ only in
# distance, far and fresh only in age.
#
#   main   A - B - C - D
#   near           \ N        main is 1 past the fork (D), idle a year
#   far        \ F            main is 2 past the fork (C, D), idle a year
#   fresh      \ R            main is 2 past the fork (C, D), touched a day ago
commit A
commit B A
commit C B
commit D C
commit N C
commit F B
commit R B
committed A 960000000
committed B 960000000
committed C 960000000
committed D 999000000
committed N 968464000
committed F 968464000
committed R 999913600

ref_set refs/heads/main D
ref_set refs/remotes/origin/HEAD D
ref_set refs/heads/near N
ref_set refs/heads/far F
ref_set refs/heads/fresh R

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

NOW=1000000000
MAX_DISTANCE=1
MAX_AGE_DAYS=30

branch_beyond_cap refs/heads/near && near=capped || near=evaluated
branch_beyond_cap refs/heads/far && far=capped || far=evaluated
branch_beyond_cap refs/heads/fresh && fresh=capped || fresh=evaluated

expected="near=evaluated far=capped fresh=evaluated"
actual="near=$near far=$far fresh=$fresh"
assert_eq "$actual" "$expected"
