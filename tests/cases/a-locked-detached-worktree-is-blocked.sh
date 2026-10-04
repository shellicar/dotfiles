#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a locked worktree with no branch is blocked, whatever else is true of its commit"

# Its commit is in main, which on its own makes it removable. The lock outranks
# that the way uncommitted changes do, because git will not remove it.
#
#   main  A - B
#   /wt/parked sits on A, detached, locked
commit A
commit B A
ref_set refs/heads/main B
ref_set refs/remotes/origin/HEAD B
detached_worktree A /wt/parked
lock_worktree /wt/parked 'claude session review (pid 4242 start 1234567)'

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="blocked${TAB}locked: claude session review (pid 4242 start 1234567)"
actual=$(detached_verdict /wt/parked A)
assert_eq "$actual" "$expected"
