#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a locked worktree gives its lock, reason and all, as the reason not to remove it"

# git refuses to remove a locked worktree. A removal offered for one can only
# fail, so it is blocked up front, and the reason shown is git's own, word for
# word, so you can tell which session holds it.

worktree_for refs/heads/feature/held /wt/held
lock_worktree /wt/held 'claude session feature/held (pid 4242 start 1234567)'

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected='locked: claude session feature/held (pid 4242 start 1234567)'
actual=$(worktree_block_reason /wt/held)
assert_eq "$actual" "$expected"
