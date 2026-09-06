#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch tangled with a published branch past main is left alone"

# Rebasing feature/top would replay feature/base's commits under new ids and the
# force-push would publish the copies, so top's pull request would show base's
# work as its own. That harm needs base to be published, which it is here.
#
# Built as a graph, not as canned answers: stubbing the reachability questions
# lets the case describe a state git cannot produce, which passes whatever the
# behaviour is.
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
ref_set refs/remotes/origin/feature/base X2
ref_set refs/heads/feature/top Y1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="none${TAB}shares history with feature/base past main"
actual=$(update_verdict . feature/top)
assert_eq "$actual" "$expected"
