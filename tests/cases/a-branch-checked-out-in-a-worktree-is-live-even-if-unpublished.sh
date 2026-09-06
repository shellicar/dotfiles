#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch checked out in a worktree is live even if it was never pushed"

# The pair to a-rebranch-leftover-does-not-block-the-rebase. Same shape, same
# lack of a remote branch, and the opposite answer, because someone is working
# in it. Replaying its commits into the branch above would leave the same work
# on both under different ids.
#
#   main   A - B - C
#   lower        \ X1        (never pushed, but checked out)
#   upper             \ Y1   (published)
commit A
commit B A
commit C B
commit X1 B
commit Y1 X1

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/lower X1
ref_set refs/heads/upper Y1
ref_set refs/remotes/origin/upper Y1

worktree_for refs/heads/lower /wt/lower

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="none${TAB}shares history with lower past main"
actual=$(update_verdict . upper)
assert_eq "$actual" "$expected"
