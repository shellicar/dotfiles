#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a local-only branch left behind by a rebranch does not block the rebase"

# The ordinary way of working: branch, commit, switch to a new branch, commit
# again, and the first branch sits there checked out nowhere and never pushed.
# Rebasing the second one replays the first's commits, and that costs nothing
# because nobody else has them. Refusing here would refuse on every rebranch.
#
#   main   A - B - C
#   old          \ X1        (never pushed)
#   new               \ Y1
commit A
commit B A
commit C B
commit X1 B
commit Y1 X1

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/old X1
ref_set refs/heads/new Y1
ref_set refs/remotes/origin/new Y1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="rebase${TAB}B"
actual=$(update_verdict . new)
assert_eq "$actual" "$expected"
