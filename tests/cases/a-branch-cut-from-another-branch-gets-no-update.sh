#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch cut from another branch is left alone and names that branch"

# Neither rebase is right here: a plain one copies the parent's commits onto
# this branch and force-pushes them, a fork-point one drops them and leaves it
# built on nothing.
#
# Built as a graph, not as canned answers. An earlier version of this case
# stubbed the reachability questions, and the state it described was one git
# cannot produce, so it passed while the behaviour was broken.
#
#   main   A - B - C
#   base        \ X1 - X2
#   top                  \ Y1
commit A
commit B A
commit C B
commit X1 B
commit X2 X1
commit Y1 X2

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/feature/base X2
ref_set refs/heads/feature/top Y1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="none${TAB}cut from feature/base, not from main"
actual=$(update_verdict . feature/top)
assert_eq "$actual" "$expected"
